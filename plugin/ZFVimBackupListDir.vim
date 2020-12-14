
command! -nargs=* -complete=dir ZFBackupListDir :call ZFBackupListDir(<q-args>)

function! ZFBackupListDir(...)
    let dirPath = get(a:, 1, '')
    if empty(dirPath)
        let dirPath = getcwd()
    endif
    let absPath = CygpathFix_absPath(dirPath)
    let backupsInDir = {}
    for backupInfo in ZFBackup_getAllBackupInfoList()
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

    let openHint = ''
    let reloadHint = ''
    let quitHint = ''
    for k in get(g:, 'ZFBackupKeymap_listDirBuffer_open', ['o', '<cr>'])
        execute 'nnoremap <silent><buffer> ' . k . ' :call ZFBackupKeymap_listDirBuffer_open()<cr>'
        if !empty(openHint)
            let openHint .= ' or '
        endif
        let openHint .= k
    endfor
    for k in get(g:, 'ZFBackupKeymap_listDirBuffer_reload', ['DD'])
        execute 'nnoremap <silent><buffer> ' . k . ' :call ZFBackupKeymap_listDirBuffer_reload()<cr>'
        if !empty(reloadHint)
            let reloadHint .= ' or '
        endif
        let reloadHint .= k
    endfor
    for k in get(g:, 'ZFBackupKeymap_listDirBuffer_quit', ['q'])
        execute 'nnoremap <silent><buffer> ' . k . ' :call ZFBackupKeymap_listDirBuffer_quit()<cr>'
        if !empty(quitHint)
            let quitHint .= ' or '
        endif
        let quitHint .= k
    endfor

    let contents = [
                \   '# backups for dir: ' . absPath,
                \   '# ' . openHint . ' to list backup for file',
                \   '# ' . reloadHint . ' to reload',
                \   '# ' . quitHint . ' or :bd to quit',
                \   '',
                \ ]
    let b:ZFBackupListDir_dirPath = absPath
    let b:ZFBackupListDir_filesToList = []
    let b:ZFBackupListDir_offset = len(contents) + 1
    let contentsTmp = []
    let maxLen = 0
    for backupInfo in values(backupsInDir)
        call add(b:ZFBackupListDir_filesToList, backupInfo['origPath'])
        let relIndex = stridx(backupInfo['origPath'], absPath)
        if relIndex == 0
            let pathInfo = strpart(backupInfo['origPath'], len(absPath))
        else
            let pathInfo = backupInfo['origPath']
        endif
        let name = fnamemodify(backupInfo['origPath'], ':t')
        if len(name) > maxLen
            let maxLen = len(name)
        endif
        call add(contentsTmp, [name, pathInfo])
    endfor
    for t in contentsTmp
        call add(contents, t[0] . repeat(' ', maxLen - len(t[0])) . ' => ' . t[1])
    endfor

    call add(contents, '')
    call setline(1, contents)
    setlocal nomodifiable nomodified
    let cursorPos = getpos('.')
    let cursorPos[1] = b:ZFBackupListDir_offset
    call setpos('.', cursorPos)

    set filetype=ZFBackupListDir
endfunction

function! ZFBackupKeymap_listDirBuffer_open()
    if !exists('b:ZFBackupListDir_dirPath') || !exists('b:ZFBackupListDir_filesToList') || !exists('b:ZFBackupListDir_offset')
        return
    endif
    let index = getpos('.')[1] - b:ZFBackupListDir_offset
    if index < 0 || index >= len(b:ZFBackupListDir_filesToList)
        return
    endif
    call ZFBackupList(b:ZFBackupListDir_filesToList[index])
endfunction
function! ZFBackupKeymap_listDirBuffer_reload()
    if !exists('b:ZFBackupListDir_dirPath') || !exists('b:ZFBackupListDir_filesToList') || !exists('b:ZFBackupListDir_offset')
        return
    endif
    let dirPath = b:ZFBackupListDir_dirPath
    call ZFBackupKeymap_listDirBuffer_quit()
    call ZFBackupListDir(dirPath)
endfunction
function! ZFBackupKeymap_listDirBuffer_quit()
    if !exists('b:ZFBackupListDir_dirPath') || !exists('b:ZFBackupListDir_filesToList') || !exists('b:ZFBackupListDir_offset')
        return
    endif
    bdelete!
endfunction

