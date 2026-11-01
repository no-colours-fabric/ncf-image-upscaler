"""Minimal Windows process declarations for the CPU worker's local Job guard."""

import ctypes as C
from ctypes import wintypes as W

k32 = C.WinDLL("kernel32", use_last_error=True)
PTR = C.c_void_p


class STARTUPINFO(C.Structure):
    _fields_ = [
        ("cb", W.DWORD),
        ("lpReserved", W.LPWSTR),
        ("lpDesktop", W.LPWSTR),
        ("lpTitle", W.LPWSTR),
        ("dwX", W.DWORD),
        ("dwY", W.DWORD),
        ("dwXSize", W.DWORD),
        ("dwYSize", W.DWORD),
        ("dwXCountChars", W.DWORD),
        ("dwYCountChars", W.DWORD),
        ("dwFillAttribute", W.DWORD),
        ("dwFlags", W.DWORD),
        ("wShowWindow", W.WORD),
        ("cbReserved2", W.WORD),
        ("lpReserved2", PTR),
        ("hStdInput", W.HANDLE),
        ("hStdOutput", W.HANDLE),
        ("hStdError", W.HANDLE),
    ]


class STARTUPINFOEX(C.Structure):
    _fields_ = [("StartupInfo", STARTUPINFO), ("lpAttributeList", PTR)]


class PROCESS_INFORMATION(C.Structure):
    _fields_ = [
        ("hProcess", W.HANDLE),
        ("hThread", W.HANDLE),
        ("dwProcessId", W.DWORD),
        ("dwThreadId", W.DWORD),
    ]


def declare(name, args, result):
    fn = getattr(k32, name)
    fn.argtypes, fn.restype = args, result
    return fn


create_process = declare(
    "CreateProcessW",
    [
        W.LPCWSTR,
        W.LPWSTR,
        PTR,
        PTR,
        W.BOOL,
        W.DWORD,
        PTR,
        W.LPCWSTR,
        C.POINTER(STARTUPINFOEX),
        C.POINTER(PROCESS_INFORMATION),
    ],
    W.BOOL,
)
wait = declare("WaitForSingleObject", [W.HANDLE, W.DWORD], W.DWORD)
terminate = declare("TerminateProcess", [W.HANDLE, W.UINT], W.BOOL)
exit_code = declare("GetExitCodeProcess", [W.HANDLE, C.POINTER(W.DWORD)], W.BOOL)
close = declare("CloseHandle", [W.HANDLE], W.BOOL)


def checked(value):
    if not value:
        raise C.WinError(C.get_last_error())
    return value
