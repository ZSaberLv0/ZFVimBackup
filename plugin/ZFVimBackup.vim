
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
        elseif executable('executable')
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
    " require `retorillo/md5.vim`
    if !exists('*MD5File')
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
        let items = split(substitute(fnamemodify(a:filePath, ':p'), '\\\+', '/', 'g'), '/')
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
        let s:backupDir = s:absPath(s:backupDir)
    endif
    return s:backupDir
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

function! ZFBackupList(...)
    call s:backupList(get(a:, 1, ''))
endfunction
command! -nargs=* -complete=file ZFBackupList :call ZFBackupList(<q-args>)

function! ZFBackupListDir(...)
    call s:backupListDir(get(a:, 1, ''))
endfunction
command! -nargs=* -complete=dir ZFBackupListDir :call ZFBackupListDir(<q-args>)

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
    let backupInfoList = s:getAllBackupInfoList()

    let interval = get(g:, 'ZFBackup_autoClean', 7 * 24 * 60 * 60)
    if interval > 0
        let epoch = localtime() - interval
        for backupInfo in backupInfoList
            if getftime(backupDir . '/' . backupInfo['backupFile']) < epoch
                silent! call delete(backupDir . '/' . backupInfo['backupFile'])
            endif
        endfor
    endif

    let maxBackup = get(g:, 'ZFBackup_maxBackup', 200)
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

function! s:absPath(path)
    if !exists('s:isCygwin')
        let s:isCygwin = has('win32unix') && executable('cygpath')
    endif

    " when shellslash is on,
    " fnamemodify seems unable to convert path separator correctly
    " with simple `:p`
    let path = fnamemodify(fnamemodify(a:path, ':.'), ':p')
    if s:isCygwin
        let path = substitute(system('cygpath -m "' . path . '"'), '[\r\n]', '', 'g')
    endif
    let path = substitute(path, '\\', '/', 'g')
    return path
endfunction

function! s:isInBackupDir(path)
    return (stridx(s:absPath(a:path), s:absPath(ZFBackup_backupDir())) == 0)
endfunction

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
                \ . '~' . s:pathEncode(s:absPath(a:origPath))
    return {
                \   'backupFile' : backupFile,
                \   'hash' : hash,
                \ }
endfunction
function! s:backupInfoDecode(backupFile)
    let backupFile = fnamemodify(a:backupFile, ':t')
    let items = split(backupFile, '\~')
    if len(items) == 5
        let time = items[1] . substitute(items[2], '-', ':', 'g')
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
    if s:isInBackupDir(filePath)
                \ || !filereadable(filePath)
                \ || (maxFileSize > 0 && getfsize(filePath) >= maxFileSize)
        return
    endif

    let origPath = s:absPath(filePath)
    let backupDir = ZFBackup_backupDir()

    " ignore file created by tempname()
    if !get(options, 'includeTempname', get(g:, 'ZFBackup_includeTempname', 0))
        if !exists('s:tempDir')
            let s:tempDir = s:absPath(fnamemodify(tempname(), ':p:h'))
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

    let backupInfoListOld = s:getBackupInfoList(origPath)
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
    let backupInfoList = s:getBackupInfoList(filePath)
    if empty(backupInfoList)
        echo '[ZFBackup] no backup found'
        return
    endif

    redraw!
    call inputsave()
    let input = input(join([
                \   '[ZFBackup] remove all backups for file?',
                \   '    file: ' . s:absPath(filePath),
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
    let absPath = s:absPath(dirPath)

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
    for backupInfo in s:getAllBackupInfoList()
        if stridx(backupInfo['origPath'], absPath) == 0
            silent! call delete(backupDir . '/' . backupInfo['backupFile'])
        endif
    endfor
endfunction

function! s:backupList(filePath)
    let filePath = a:filePath
    if empty(filePath)
        let filePath = expand('%')
    endif
    if empty(filePath)
        call ZFBackupListDir(getcwd())
        return
    endif
    let backupInfoList = s:getBackupInfoList(filePath)
    if empty(backupInfoList)
        echo '[ZFBackup] no backup found'
        return
    endif
    if len(backupInfoList) == 1
        let choice = 0
    else
        let inputlist = ['[ZFBackup] select backup file to diff:']
        call add(inputlist, '')
        for i in range(len(backupInfoList))
            call add(inputlist, '    [' . (i+1) . ']: ' . backupInfoList[i]['info'])
        endfor
        call add(inputlist, '')
        call inputsave()
        let choice = inputlist(inputlist) - 1
        call inputrestore()
        if choice < 0 || choice >= len(backupInfoList)
            redraw!
            echo '[ZFBackup] canceled'
            return
        endif
    endif

    execute 'tabedit ' . substitute(ZFBackup_backupDir() . '/' . backupInfoList[choice]['backupFile'], ' ', '\\ ', 'g')
    diffthis
    call s:diffBufferKeymapSetup()
    execute 'file ' . backupInfoList[choice]['info']
    setlocal buftype=nofile bufhidden=wipe noswapfile nomodifiable

    vsplit
    wincmd l
    let existBuf = bufnr(substitute(filePath, '\\', '/', 'g'))
    if existBuf != -1
        execute ':b' . existBuf
    else
        execute 'edit ' . substitute(filePath, ' ', '\\ ', 'g')
    endif
    diffthis
    call s:diffBufferKeymapSetup()

    execute "normal! \<c-w>l]czz"
    redraw!
    echo '[ZFBackup] ' . backupInfoList[choice]['info']
endfunction

augroup ZFBackup_diffBuffer_augroup
    autocmd!
    autocmd User ZFBackupDiffBufferSetup silent
    autocmd User ZFBackupDiffBufferCleanup silent
augroup END
function! s:diffBufferKeymapSetup()
    for k in get(g:, 'ZFBackup_diffBufferKeymap_quit', ['q'])
        execute 'nnoremap <silent><buffer> ' . k . ' :call ZFBackup_diffBufferKeymap_quit()<cr>'
    endfor
    doautocmd User ZFBackupDiffBufferSetup
endfunction
function! ZFBackup_diffBufferKeymap_quit()
    if s:isInBackupDir(expand('%'))
        wincmd l
    endif
    silent! diffoff
    for k in get(g:, 'ZFBackup_diffBufferKeymap_quit', ['q'])
        execute 'silent! unmap <buffer> ' . k
    endfor
    doautocmd User ZFBackupDiffBufferCleanup
    wincmd h
    doautocmd User ZFBackupDiffBufferCleanup
    silent! bdelete!
    tabclose
endfunction

function! s:backupListDir(dirPath)
    let dirPath = a:dirPath
    if empty(dirPath)
        let dirPath = getcwd()
    endif
    let absPath = s:absPath(dirPath)
    let backupsInDir = {}
    for backupInfo in s:getAllBackupInfoList()
        if stridx(backupInfo['origPath'], absPath) == 0
            let backupsInDir[backupInfo['origPath']] = backupInfo
        endif
    endfor
    if empty(backupsInDir)
        echo '[ZFBackup] no backup found'
        return
    endif
    if len(backupsInDir) == 1
        call ZFBackupList(values(backupsInDir)[0]['origPath'])
        return
    endif

    tabnew
    file ZFBackupListDir
    setlocal buftype=nofile bufhidden=wipe noswapfile
    let contents = [
                \   '# o or <cr> to list backup for file',
                \   '# q or :bd to quit',
                \   '',
                \ ]
    let b:ZFBackup_filesToList = []
    let b:ZFBackup_offset = len(contents) + 1
    for backupInfo in values(backupsInDir)
        call add(contents, fnamemodify(backupInfo['origPath'], ':t') . '    => ' . backupInfo['origPath'])
        call add(b:ZFBackup_filesToList, backupInfo['origPath'])
    endfor
    call add(contents, '')
    call setline(1, contents)
    setlocal nomodifiable nomodified
    let cursorPos = getpos('.')
    let cursorPos[1] = b:ZFBackup_offset
    call setpos('.', cursorPos)

    for k in get(g:, 'ZFBackup_listBufferKeymap_open', ['o', '<cr>'])
        execute 'nnoremap <silent><buffer> ' . k . ' :call ZFBackup_listBufferKeymap_open()<cr>'
    endfor
    for k in get(g:, 'ZFBackup_listBufferKeymap_quit', ['q'])
        execute 'nnoremap <silent><buffer> ' . k . ' :call ZFBackup_listBufferKeymap_quit()<cr>'
    endfor
    doautocmd User ZFBackupListBufferSetup
endfunction
augroup ZFBackup_listBuffer_augroup
    autocmd!
    autocmd User ZFBackupListBufferSetup silent
    autocmd User ZFBackupListBufferCleanup silent
augroup END

function! ZFBackup_listBufferKeymap_open()
    if !exists('b:ZFBackup_filesToList') || !exists('b:ZFBackup_offset')
        return
    endif
    let index = getpos('.')[1] - b:ZFBackup_offset
    if index < 0 || index >= len(b:ZFBackup_filesToList)
        return
    endif
    call ZFBackupList(b:ZFBackup_filesToList[index])
endfunction
function! ZFBackup_listBufferKeymap_quit()
    doautocmd User ZFBackupListBufferCleanup
    bdelete!
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
    if s:isInBackupDir(filePath)
        return []
    endif
    let name = fnamemodify(filePath, ':t')
    if empty(name)
        return []
    endif

    let absPath = s:absPath(filePath)
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

