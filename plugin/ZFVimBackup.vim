
" ============================================================
if !exists('g:ZFBackup_path')
    let g:ZFBackup_path = ''
endif

" ============================================================
if !exists('g:ZFBackup_backupFunc')
    let g:ZFBackup_backupFunc = 'ZFBackup_backupFunc'
endif
function! ZFBackup_backupFunc(from, to)
    " on Windows, very long path would result to fail, simply ignore it
    try
        " use read write instead of copy,
        " to ensure latest getftime()
        silent! call writefile(readfile(a:from, 'b'), a:to, 'b')
    catch
    endtry
endfunction

" ============================================================
if !exists('g:ZFBackup_hashFunc')
    let g:ZFBackup_hashFunc = 'ZFBackup_hashFunc'
endif
function! ZFBackup_hashFunc(filePath)
    if !exists('s:hashFunc')
        if executable('md5sum')
            let s:hashFunc = function('ZFBackup_hashFunc_md5sum')
        elseif executable('md5')
            let s:hashFunc = function('ZFBackup_hashFunc_md5')
        elseif executable('certutil')
            let s:hashFunc = function('ZFBackup_hashFunc_certutil')
        else
            let s:hashFunc = function('ZFBackup_hashFunc_fallback')
        endif
    endif
    return s:hashFunc(a:filePath)
endfunction
function! ZFBackup_hashFunc_md5(filePath)
    let ret = system('md5 -q "' . a:filePath . '"')
    if !exists('v:shell_error') || v:shell_error != 0
        return ''
    endif
    " \<[a-f0-9]{32}\>
    return tolower(matchstr(ret, '\<[a-f0-9]\{32}\>'))
endfunction
function! ZFBackup_hashFunc_md5sum(filePath)
    let ret = system('md5sum "' . a:filePath . '"')
    if !exists('v:shell_error') || v:shell_error != 0
        return ''
    endif
    " \<[a-f0-9]{32}\>
    return tolower(matchstr(ret, '\<[a-f0-9]\{32}\>'))
endfunction
function! ZFBackup_hashFunc_certutil(filePath)
    let ret = system('certutil -hashfile "' . substitute(a:filePath, '/', '\\', 'g') . '" MD5')
    " \<([a-f0-9][a-f0-9] ){15}[a-f0-9][a-f0-9]\>
    let ret = matchstr(ret, '\<\([a-f0-9][a-f0-9] \)\{15}[a-f0-9][a-f0-9]\>')
    return tolower(substitute(ret, ' ', '', 'g'))
endfunction
function! ZFBackup_hashFunc_fallback(filePath)
    " require `retorillo/md5.vim`, may be very slow
    if !exists('*MD5File') || !get(g:, 'ZFBackup_hashFunc_fallback_enable', 0)
        return ''
    endif
    return MD5File(a:filePath)
endfunction

" ============================================================
if !exists('g:ZFBackup_backupFilter')
    let g:ZFBackup_backupFilter = {}
endif
if get(g:, 'ZFBackup_backupFilterEnableDefault', 1)
    if !exists('g:ZFIgnoreOptionDefault')
        let g:ZFIgnoreOptionDefault = {}
    endif
    if !exists("g:ZFIgnoreOptionDefault['ZFBackup']")
        let g:ZFIgnoreOptionDefault['ZFBackup'] = 0
    endif

    function! ZFBackup_backupFilterDefault(filePath)
        if !exists('*ZFIgnoreGet')
            return -1
        endif
        let ignoreData = ZFIgnoreGet(get(g:, 'ZFIgnoreOption_ZFBackup', {
                    \   'ZFBackup' : 1,
                    \ }))
        let items = split(CygpathFix_absPath(a:filePath), '/')
        let fileName = items[-1]
        for p in ignoreData['file']
            let pattern = ZFIgnorePatternToRegexp(p)
            if pattern != '' && match(fileName, pattern) == 0
                return 1
            endif
        endfor
        if len(items) >= 2
            for p in ignoreData['dir']
                let pattern = ZFIgnorePatternToRegexp(p)
                if pattern != ''
                    for dir in items[0:-2]
                        if match(dir, pattern) == 0
                            return 1
                        endif
                    endfor
                endif
            endfor
        endif
        return -1
    endfunction
    let g:ZFBackup_backupFilter['ZFBackup_backupFilterDefault'] = function('ZFBackup_backupFilterDefault')
endif


" ============================================================
function! ZFBackup_backupDir()
    if empty(get(s:, 'backupDir', ''))
        let cacheDir = get(g:, 'ZFBackup_path', '')
        if empty(cacheDir)
            let cacheDir = get(g:, 'zf_vim_cache_path', '')
            if empty(cacheDir)
                let cacheDir = $HOME . '/.vim_cache'
            endif
            let s:backupDir = cacheDir . '/ZFBackup'
        else
            let s:backupDir = cacheDir
        endif
        let s:backupDir = CygpathFix_absPath(s:backupDir)
    endif
    return s:backupDir
endfunction

function! ZFBackup_isInBackupDir(path)
    return (stridx(CygpathFix_absPath(a:path), CygpathFix_absPath(ZFBackup_backupDir())) == 0)
endfunction

function! CygpathFix_absPath(path)
    if len(a:path) <= 0|return ''|endif
    if !exists('g:CygpathFix_isCygwin')
        let g:CygpathFix_isCygwin = has('win32unix') && executable('cygpath')
    endif
    let path = fnamemodify(a:path, ':p')
    if !empty(path) && g:CygpathFix_isCygwin
        if 0 " cygpath is really slow
            let path = substitute(system('cygpath -m "' . path . '"'), '[\r\n]', '', 'g')
        else
            if match(path, '^/cygdrive/') >= 0
                let path = toupper(strpart(path, len('/cygdrive/'), 1)) . ':' . strpart(path, len('/cygdrive/') + 1)
            else
                if !exists('g:CygpathFix_cygwinPrefix')
                    let g:CygpathFix_cygwinPrefix = substitute(system('cygpath -m /'), '[\r\n]', '', 'g')
                endif
                let path = g:CygpathFix_cygwinPrefix . path
            endif
        endif
    endif
    return substitute(substitute(path, '\\', '/', 'g'), '\%(\/\)\@<!\/\+$', '', '') " (?<!\/)\/+$
endfunction

" param1: filePath
" param2: options: {
"   'maxFileSize' : '',
"   'includeTempname' : '',
"   'backupFilter' : {},
" }
function! ZFBackupSave(...)
    call s:backupSave(get(a:, 1, ''), get(a:, 2, {}))
endfunction
command! -nargs=* -complete=file ZFBackupSave :call ZFBackupSave(<q-args>)

function! ZFBackupSaveDir(...)
    let dirPath = get(a:, 1, '')
    if empty(dirPath)
        let dirPath = getcwd()
    endif
    let option = get(a:, 2, {})
    for f in extend(split(globpath(dirPath, '**/*.*'), "\n"), split(globpath(dirPath, '**/.[^.]*'), "\n"))
        call ZFBackupSave(f, option)
    endfor
endfunction
command! -nargs=* -complete=file ZFBackupSaveDir :call ZFBackupSaveDir(<q-args>)

function! ZFBackupRemove(...)
    call s:backupRemove(get(a:, 1, ''))
endfunction
command! -nargs=* -complete=file ZFBackupRemove :call ZFBackupRemove(<q-args>)

function! ZFBackupRemoveDir(...)
    call s:backupRemoveDir(get(a:, 1, ''))
endfunction
command! -nargs=* -complete=file ZFBackupRemoveDir :call ZFBackupRemoveDir(<q-args>)

" return: [
"   {
"     'backupFile' : 'backup file name under backupDir',
"     'origPath' : 'original file abs path',
"     'hash' : 'hash of the file',
"     'time' : 'backup saved time, string',
"     'info' : 'a short info to show the backup',
"   },
" ]
function! ZFBackup_getBackupInfoList(...)
    return s:getBackupInfoList(get(a:, 1, ''))
endfunction
function! ZFBackup_getAllBackupInfoList()
    return s:getAllBackupInfoList()
endfunction

function! ZFBackup_clean()
    for file in s:getAllBackupFilePath()
        if filewritable(file)
            silent! call delete(file)
        endif
    endfor
endfunction

function! ZFBackup_enable()
    augroup ZFBackup_enable_augroup
        autocmd!
        autocmd BufWritePre * silent! call ZFBackupSave(expand('<afile>'))
        autocmd BufWritePost * silent! call ZFBackupSave(expand('<afile>'))
    augroup END
endfunction
function! ZFBackup_disable()
    augroup ZFBackup_enable_augroup
        autocmd!
    augroup END
endfunction
if get(g:, 'ZFBackup_autoEnable', 1)
    call ZFBackup_enable()
endif

function! s:ZFBackup_autoClean_sortFunc(backupInfo1, backupInfo2)
    if a:backupInfo1['time'] == a:backupInfo2['time']
        return 0
    elseif a:backupInfo1['time'] < a:backupInfo2['time']
        return 1
    else
        return -1
    endif
endfunction
function! ZFBackup_autoClean()
    let backupDir = ZFBackup_backupDir()
    let backupInfoList = ZFBackup_getAllBackupInfoList()

    let interval = get(g:, 'ZFBackup_autoClean', 7 * 24 * 60 * 60)
    if interval > 0
        let epoch = localtime() - interval
        for backupInfo in backupInfoList
            if getftime(backupDir . '/' . backupInfo['backupFile']) < epoch
                silent! call delete(backupDir . '/' . backupInfo['backupFile'])
            endif
        endfor
    endif

    let maxBackup = get(g:, 'ZFBackup_maxBackup', 500)
    if maxBackup > 0
        call sort(backupInfoList, function('s:ZFBackup_autoClean_sortFunc'))
        if maxBackup <= len(backupInfoList) - 1
            for i in range(maxBackup, len(backupInfoList) - 1)
                silent! call delete(backupDir . '/' . backupInfoList[i]['backupFile'])
            endfor
        endif
    endif
endfunction
augroup ZFBackup_autoClean_augroup
    autocmd!
    autocmd VimLeavePre call ZFBackup_autoClean()
augroup END

" ============================================================
function! s:pathEncode(file)
    let ret = a:file
    let ret = substitute(ret, ';', ';ES;', 'g')
    let ret = substitute(ret, '[/\\]', ';PS;', 'g')
    let ret = substitute(ret, ':', ';DS;', 'g')
    let ret = substitute(ret, '\~', ';SS;', 'g')
    return ret
endfunction
function! s:pathDecode(file)
    let ret = a:file
    let ret = substitute(ret, ';ES;', ';', 'g')
    let ret = substitute(ret, ';PS;', '/', 'g')
    let ret = substitute(ret, ';DS;', ':', 'g')
    let ret = substitute(ret, ';SS;', '\~', 'g')
    return ret
endfunction

" file_name_encoded~2020-01-01~23-59-59~hash~full_path_encoded
function! s:backupInfoEncode(origPath)
    if !exists('*' . g:ZFBackup_hashFunc)
        return {}
    endif
    let Fn_hashFunc = function(g:ZFBackup_hashFunc)
    let hash = Fn_hashFunc(a:origPath)
    if type(hash) != type('')
        let hash = string(hash)
    endif
    if hash == ''
        return {}
    endif
    let backupFile = s:pathEncode(fnamemodify(a:origPath, ':t'))
                \ . '~' . strftime('%Y-%m-%d~%H-%M-%S')
                \ . '~' . s:pathEncode(hash)
                \ . '~' . s:pathEncode(CygpathFix_absPath(a:origPath))
    return {
                \   'backupFile' : backupFile,
                \   'hash' : hash,
                \ }
endfunction
function! s:backupInfoDecode(backupFile)
    let backupFile = fnamemodify(a:backupFile, ':t')
    let items = split(backupFile, '\~')
    if len(items) == 5
        let time = items[1] . ' ' . substitute(items[2], '-', ':', 'g')
        let hash = s:pathDecode(items[3])
        let origPath = s:pathDecode(items[4])
        return {
                    \   'backupFile' : backupFile,
                    \   'origPath' : origPath,
                    \   'hash' : hash,
                    \   'time' : time,
                    \   'info' : '(' . time . ') ' . fnamemodify(origPath, ':t'),
                    \ }
    endif
    return {
                \   'backupFile' : backupFile,
                \   'origPath' : '',
                \   'hash' : '',
                \   'time' : '',
                \   'info' : '',
                \ }
endfunction

function! s:getAllBackupFilePath(...)
    let name = get(a:, 1, '')
    let backupDir = ZFBackup_backupDir()
    if empty(name)
        return extend(split(glob(backupDir . '/*', 1), "\n"), split(glob(backupDir . '/.[^.]*', 1), "\n"))
    else
        return split(glob(backupDir . '/' . name . '~*', 1), "\n")
    endif
endfunction

" ============================================================

function! s:backupSave(filePath, options)
    let filePath = a:filePath
    let options = a:options
    if empty(filePath)
        let filePath = expand('%')
    endif
    if empty(filePath)
        return
    endif
    let maxFileSize = get(options, 'maxFileSize', get(g:, 'ZFBackup_maxFileSize', 2 * 1024 * 1024))
    if ZFBackup_isInBackupDir(filePath)
                \ || !filereadable(filePath)
                \ || (maxFileSize > 0 && getfsize(filePath) >= maxFileSize)
        return
    endif

    let origPath = CygpathFix_absPath(filePath)
    let backupDir = ZFBackup_backupDir()

    " ignore file created by tempname()
    if !get(options, 'includeTempname', get(g:, 'ZFBackup_includeTempname', 0))
        if !exists('s:tempDir')
            let s:tempDir = CygpathFix_absPath(fnamemodify(tempname(), ':h'))
        endif
        if stridx(origPath, s:tempDir) == 0
            return
        endif
    endif

    let backupFilter = get(options, 'backupFilter', g:ZFBackup_backupFilter)
    if !empty(backupFilter)
        for Filter in values(backupFilter)
            let filterResult = Filter(origPath)
            if filterResult == 1
                return
            elseif filterResult == 0
                break
            endif
        endfor
    endif

    let backupInfoNew = s:backupInfoEncode(origPath)
    if empty(backupInfoNew)
        return
    endif

    if !isdirectory(backupDir)
        silent! call mkdir(backupDir, 'p')
    endif
    let Fn_backupFunc = function(g:ZFBackup_backupFunc)

    let backupInfoListOld = ZFBackup_getBackupInfoList(origPath)
    if !empty(backupInfoListOld)
        for i in range(len(backupInfoListOld))
            if backupInfoListOld[i]['hash'] == backupInfoNew['hash']
                " move to latest
                if i != 0
                    silent! call delete(backupDir . '/' . backupInfoListOld[i]['backupFile'])
                    call Fn_backupFunc(origPath, backupDir . '/' . backupInfoNew['backupFile'])
                endif
                return
            endif
        endfor
    endif

    " perform backup
    call Fn_backupFunc(origPath, backupDir . '/' . backupInfoNew['backupFile'])

    let maxBackup = get(g:, 'ZFBackup_maxBackupPerFile', 5)
    if maxBackup > 0
        if maxBackup <= len(backupInfoListOld)
            for i in range(maxBackup - 1, len(backupInfoListOld) - 1)
                silent! call delete(backupDir . '/' . backupInfoListOld[i]['backupFile'])
            endfor
        endif
    endif

    call ZFBackup_autoClean()
endfunction

function! s:backupRemove(filePath)
    let filePath = a:filePath
    if empty(filePath)
        let filePath = expand('%')
    endif
    let backupInfoList = ZFBackup_getBackupInfoList(filePath)
    if empty(backupInfoList)
        echo '[ZFBackup] no backup found'
        return
    endif

    redraw!
    call inputsave()
    let input = input(join([
                \   '[ZFBackup] remove all backups for file?',
                \   '    file: ' . CygpathFix_absPath(filePath),
                \   '',
                \   'enter `got it` to remove: ',
                \ ], "\n"))
    call inputrestore()
    redraw!
    if input != 'got it'
        echo '[ZFBackup] canceled'
        return
    endif

    let backupDir = ZFBackup_backupDir()
    for backupInfo in backupInfoList
        silent! call delete(backupDir . '/' . backupInfo['backupFile'])
    endfor
    echo '[ZFBackup] backup removed'
endfunction

function! s:backupRemoveDir(dirPath)
    let dirPath = a:dirPath
    if empty(dirPath)
        let dirPath = getcwd()
    endif
    let absPath = CygpathFix_absPath(dirPath)

    redraw!
    call inputsave()
    let input = input(join([
                \   '[ZFBackup] remove all backups for dir?',
                \   '    dir: ' . absPath,
                \   '',
                \   'enter `got it` to remove: ',
                \ ], "\n"))
    call inputrestore()
    redraw!
    if input != 'got it'
        echo '[ZFBackup] canceled'
        return
    endif

    let backupDir = ZFBackup_backupDir()
    for backupInfo in ZFBackup_getAllBackupInfoList()
        if stridx(backupInfo['origPath'], absPath) == 0
            silent! call delete(backupDir . '/' . backupInfo['backupFile'])
        endif
    endfor
endfunction

function! s:getBackupInfoList_sortFunc(backupInfo1, backupInfo2)
    if a:backupInfo1['backupFile'] == a:backupInfo2['backupFile']
        return 0
    elseif a:backupInfo1['backupFile'] < a:backupInfo2['backupFile']
        return 1
    else
        return -1
    endif
endfunction
function! s:getBackupInfoList(filePath)
    let filePath = a:filePath
    if empty(filePath)
        let filePath = expand('%')
    endif
    if ZFBackup_isInBackupDir(filePath)
        return []
    endif
    let name = fnamemodify(filePath, ':t')
    if empty(name)
        return []
    endif

    let absPath = CygpathFix_absPath(filePath)
    let ret = []
    for backupFile in s:getAllBackupFilePath(name)
        let backupInfo = s:backupInfoDecode(backupFile)
        if !empty(backupInfo['origPath']) && backupInfo['origPath'] == absPath
            call add(ret, backupInfo)
        endif
    endfor
    call sort(ret, function('s:getBackupInfoList_sortFunc'))
    return ret
endfunction
function! s:getAllBackupInfoList()
    let ret = []
    for backupFile in s:getAllBackupFilePath()
        let backupInfo = s:backupInfoDecode(backupFile)
        if !empty(backupInfo['origPath'])
            call add(ret, backupInfo)
        endif
    endfor
    call sort(ret, function('s:getBackupInfoList_sortFunc'))
    return ret
endfunction

