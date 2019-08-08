let g:firenvim_port_opened = 0

" Entry point of the vim-side of the extension.
" This function does the following things:
" - Get a security token from neovim's stdin
" - Bind itself to a TCP port
" - Write the security token + tcp port number to stdout()
" - Take care of forwarding messages received on the TCP port to neovim
function! firenvim#run()
        " Write messages to stdout according to the format expected by
        " Firefox's native messaging protocol
        function! WriteStdout(id, data)
                if strlen(a:data) > 254
                        throw "firenvim#run()WriteStdout doesn't handle messages more than 254 bytes long."
                endif
                call chansend(a:id, [printf("%c\n\n\n", strlen(a:data)) . a:data])
                call chanclose(a:id)
        endfunction
        function! OnStdin(id, data, event)
                if g:firenvim_port_opened
                        return
                endif
                let l:params = json_decode(matchstr(a:data[0], "{[^}]*}"))
                let l:port = luaeval("require('firenvim').start_server('" .
                                        \ l:params["password"] . "', '" .
                                        \ l:params["origin"] .
                                        \ "')")
                let g:firenvim_port_opened = 1
                call WriteStdout(a:id, l:port)
                call chanclose(a:id)
        endfunction
        let l:chanid = stdioopen({ 'on_stdin': 'OnStdin' })
endfunction

function! s:get_executable_name()
        if has("win32")
                return "firenvim.bat"
        endif
        return "firenvim"
endfunction

function! s:get_data_dir_path()
        let l:xdg_data_home = $XDG_DATA_HOME
        if l:xdg_data_home == ""
                let l:xdg_data_home = fnamemodify(stdpath("data"), ":h")
        endif
        return s:build_path([l:xdg_data_home, "firenvim"])
endfunction

function! s:firefox_config_exists()
        let l:p = [$HOME, '.mozilla']
        if has('mac')
                let l:p = [$HOME, 'Library', 'Application Support', 'Mozilla']
        elseif has('win32')
                let l:p = [$HOME, 'AppData', 'Roaming', 'Mozilla', 'Firefox']
        end
        return isdirectory(s:build_path(l:p))
endfunction

function! s:get_firefox_manifest_dir_path()
        if has('mac')
                return s:build_path([$HOME, 'Library', 'Application Support', 'Mozilla', 'NativeMessagingHosts'])
        elseif has('win32')
                return s:get_data_dir_path()
        end
        return s:build_path([$HOME, '.mozilla', 'native-messaging-hosts'])
endfunction

function! s:chrome_config_exists()
        let l:p = [$HOME, '.config', 'google-chrome']
        if has('mac')
                let l:p = [$HOME, 'Library', 'Application Support', 'Google', 'Chrome']
        elseif has('win32')
                let l:p = [$HOME, 'AppData', 'Local', 'Google', 'Chrome']
        end
        return isdirectory(s:build_path(l:p))
endfunction

function! s:get_chrome_manifest_dir_path()
        if has('mac')
                return s:build_path([$HOME, 'Library', 'Application Support', 'Google', 'Chrome', 'NativeMessagingHosts'])
        elseif has('win32')
                return s:get_data_dir_path()
        end
        return s:build_path([$HOME, '.config', 'google-chrome', 'NativeMessagingHosts'])
endfunction

function! s:chromium_config_exists()
        let l:p = [$HOME, '.config', 'chromium']
        if has('mac')
                let l:p = [$HOME, 'Library', 'Application Support', 'Chromium']
        elseif has('win32')
                let l:p = [$HOME, 'AppData', 'Local', 'Chromium']
        end
        return isdirectory(s:build_path(l:p))
endfunction

function! s:get_chromium_manifest_dir_path()
        if has('mac')
                return s:build_path([$HOME, 'Library', 'Application Support', 'Chromium', 'NativeMessagingHosts'])
        elseif has('win32')
                return s:get_data_dir_path()
        end
        return s:build_path([$HOME, '.config', 'chromium', 'NativeMessagingHosts'])
endfunction

function! s:get_executable_content(data_dir)
        if has("win32")
                return  "@echo off\n" .
                                        \ "cd " . a:data_dir . "\n" .
                                        \ v:progpath . " --headless -c FirenvimRun\n"
        endif
        return "#!/bin/sh\n
                                \cd " . a:data_dir . "\n
                                \exec '" . v:progpath . "' --headless -c 'call firenvim#run()'\n
                                \"
endfunction

function! s:get_manifest_beginning(execute_nvim_path)
        return '{
                                \ "name": "firenvim",
                                \ "description": "Turn Firefox into a Neovim client.",
                                \ "path": "' . substitute(a:execute_nvim_path, '\', '\\\\', 'g') . '",
                                \ "type": "stdio",
                                \'
endfunction

function! s:get_chrome_manifest(execute_nvim_path)
        return s:get_manifest_beginning(a:execute_nvim_path) .
                                \' "allowed_origins": [
                                \ "chrome-extension://mmmllmhmimdejghpafjolabnkfphckke/"
                                \ ]
                                \}'
endfunction

function! s:get_firefox_manifest(execute_nvim_path)
        return s:get_manifest_beginning(a:execute_nvim_path) .
                                \' "allowed_extensions": ["firenvim@lacamb.re"]
                                \}'
endfunction

function! s:key_to_ps1_str(key, manifest_path)
        let l:ps1_content = ""
        let l:key_arr = split(l:key, '\')
        let l:i = 0
        for l:i in range(2, len(key_arr) - 1)
                let l:ps1_content = l:ps1_content . "\nNew-Item -Path \"" . join(key_arr[0:i], '\') . '" -ErrorAction SilentlyContinue'
        endfor
        " Then, assign a value to it
        return l:ps1_content . "\nSet-Item -Path \"" .
                                \ l:key .
                                \ '\" -Value "' . l:manifest_path . '" ' .
                                \ '-ErrorAction SilentlyContinue'
endfunction

" Simple helper to build the right path depending on the platform.
function! s:build_path(list)
        let l:path_separator = "/"
        if has("win32")
                let l:path_separator = "\\"
        endif
        return join(a:list, path_separator)
endfunction

" Installing firenvim requires several steps:
" - Create a batch/shell script that takes care of starting neovim with the
"   right arguments. This is needed because the webextension api doesn't let
"   users specify what arguments programs should be started with
" - Create a manifest file that lets the browser know where the script created
"   can be found
" - On windows, also create a registry key that points to the native manifest
"
" Manifest paths & registry stuff are specified here: 
" https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Native_manifests#Manifest_location
function! firenvim#install(...)
        if !has("nvim-0.4.0")
                echoerr "Error: nvim version >= 0.4.0 required. Aborting."
                return
        endif

        let l:force_install = 0
        if a:0 > 0
                let l:force_install = a:1
        endif

        " Decide where the script responsible for starting neovim should be
        let l:data_dir = s:get_data_dir_path()
        let l:execute_nvim_path = s:build_path([l:data_dir, s:get_executable_name()])
        " Write said script to said path
        let l:execute_nvim = s:get_executable_content(l:data_dir)

        call mkdir(l:data_dir, "p", 0700)
        call writefile(split(l:execute_nvim, "\n"), l:execute_nvim_path)
        call setfperm(l:execute_nvim_path, "rwx------")

        let l:browsers = {
                                \"firefox": {
                                \ "has_config": s:firefox_config_exists(),
                                \ "manifest_content": function('s:get_firefox_manifest'),
                                \ "manifest_dir_path": function('s:get_firefox_manifest_dir_path'),
                                \ "registry_key": 'HKCU:\Software\Mozilla\NativeMessagingHosts\firenvim',
                                \},
                                \"chrome": {
                                \ "has_config": s:chrome_config_exists(),
                                \ "manifest_content": function('s:get_chrome_manifest'),
                                \ "manifest_dir_path": function('s:get_chrome_manifest_dir_path'),
                                \ "registry_key": 'HKCU:\Software\Google\Chrome\NativeMessagingHosts\firenvim',
                                \},
                                \"chromium": {
                                \ "has_config": s:chromium_config_exists(),
                                \ "manifest_content": function('s:get_chrome_manifest'),
                                \ "manifest_dir_path": function('s:get_chromium_manifest_dir_path'),
                                \ "registry_key": 'HKCU:\Software\Chromium\NativeMessagingHosts\firenvim',
                                \},
                                \}

        let l:powershell_script = ""
        for l:name in ["firefox", "chrome", "chromium"]
                let l:cur_browser = l:browsers[l:name]
                if !l:cur_browser["has_config"] && !l:force_install
                        echo "No config detected for " . l:name . ". Skipping."
                        continue
                endif

                let l:manifest_content = l:cur_browser["manifest_content"](l:execute_nvim_path)
                let l:manifest_dir_path = l:cur_browser["manifest_dir_path"]()
                let l:manifest_path = s:build_path([l:manifest_dir_path, "firenvim.json"])

                call mkdir(l:manifest_dir_path, "p", 0700)
                call writefile([l:manifest_content], l:manifest_path)
                call setfperm(l:manifest_path, "rw-------")

                echo "Installed native manifest for " . l:name . "."

                if has('win32')
                        echo "Creating registry key for " . l:name . ". This may take a while."
                        " On windows, also create a registry key. We
                        " do this by writing a powershell script to a
                        " file and executing it.
                        let l:ps1 = s:key_to_ps1_str(l:cur_browser["registry_key"],
                                                \ l:manifest_path)
                        let l:ps1_path = s:build_path([l:manifest_dir_path, l:cur_browser . ".ps1"])
                        call writefile(split(l:ps1_content, "\n"), l:ps1_path)
                        call setfperm(l:ps1_path, "rwx------")
                        call system('powershell "' . l:ps1_path . '"')

                        echo "Created registry key for " . l:name . "."
                endif
        endfor
endfunction
