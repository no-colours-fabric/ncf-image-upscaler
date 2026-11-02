"""Process-local Windows Job memory cap. No system settings or profiles changed."""

import ctypes as C
import os
import subprocess
from ctypes import wintypes as W

from win_api import (
    PROCESS_INFORMATION,
    STARTUPINFOEX,
    checked,
    close,
    create_process,
    exit_code,
    k32,
    terminate,
    wait,
)

SIZE = C.c_size_t


class BASIC(C.Structure):
    _fields_ = [
        ("PerProcessUserTimeLimit", C.c_int64),
        ("PerJobUserTimeLimit", C.c_int64),
        ("LimitFlags", W.DWORD),
        ("MinimumWorkingSetSize", SIZE),
        ("MaximumWorkingSetSize", SIZE),
        ("ActiveProcessLimit", W.DWORD),
        ("Affinity", SIZE),
        ("PriorityClass", W.DWORD),
        ("SchedulingClass", W.DWORD),
    ]


class IOC(C.Structure):
    _fields_ = [
        (name, C.c_uint64)
        for name in (
            "ReadOperationCount",
            "WriteOperationCount",
            "OtherOperationCount",
            "ReadTransferCount",
            "WriteTransferCount",
            "OtherTransferCount",
        )
    ]


class EXTENDED(C.Structure):
    _fields_ = [
        ("BasicLimitInformation", BASIC),
        ("IoInfo", IOC),
        ("ProcessMemoryLimit", SIZE),
        ("JobMemoryLimit", SIZE),
        ("PeakProcessMemoryUsed", SIZE),
        ("PeakJobMemoryUsed", SIZE),
    ]


class PERFORMANCE(C.Structure):
    _fields_ = (
        [("cb", W.DWORD)]
        + [
            (name, SIZE)
            for name in (
                "CommitTotal",
                "CommitLimit",
                "CommitPeak",
                "PhysicalTotal",
                "PhysicalAvailable",
                "SystemCache",
                "KernelTotal",
                "KernelPaged",
                "KernelNonpaged",
                "PageSize",
            )
        ]
        + [(name, W.DWORD) for name in ("HandleCount", "ProcessCount", "ThreadCount")]
    )


def declare(dll, name, args, result):
    function = getattr(dll, name)
    function.argtypes = args
    function.restype = result
    return function


new_job = declare(k32, "CreateJobObjectW", [C.c_void_p, W.LPCWSTR], W.HANDLE)
set_job = declare(k32, "SetInformationJobObject", [W.HANDLE, C.c_int, C.c_void_p, W.DWORD], W.BOOL)
query_job = declare(
    k32, "QueryInformationJobObject", [W.HANDLE, C.c_int, C.c_void_p, W.DWORD, C.c_void_p], W.BOOL
)
assign = declare(k32, "AssignProcessToJobObject", [W.HANDLE, W.HANDLE], W.BOOL)
resume = declare(k32, "ResumeThread", [W.HANDLE], W.DWORD)
get_performance = declare(
    C.WinDLL("psapi", use_last_error=True),
    "GetPerformanceInfo",
    [C.POINTER(PERFORMANCE), W.DWORD],
    W.BOOL,
)


def system_memory():
    data = PERFORMANCE()
    data.cb = C.sizeof(data)
    checked(get_performance(C.byref(data), C.sizeof(data)))
    return {
        "physical_available_bytes": int(data.PhysicalAvailable * data.PageSize),
        "commit_headroom_bytes": int((data.CommitLimit - data.CommitTotal) * data.PageSize),
        "commit_total_bytes": int(data.CommitTotal * data.PageSize),
        "commit_limit_bytes": int(data.CommitLimit * data.PageSize),
    }


class GuardedProcess:
    def __init__(self, command, log_path, cwd, limit_bytes=8 * 2**30):
        import msvcrt

        self.job = new_job(None, None)
        checked(self.job)
        self.pi = PROCESS_INFORMATION()
        self.log = None
        self.closed = False
        self.limit = limit_bytes
        try:
            limits = EXTENDED()
            limits.BasicLimitInformation.LimitFlags = 0x2000 | 0x100 | 0x200 | 0x8
            # Keep the child process tree bounded, including any interpreter launcher.
            # Permit that stub plus exactly one real interpreter, both in this job.
            limits.BasicLimitInformation.ActiveProcessLimit = 2
            limits.ProcessMemoryLimit = limit_bytes
            limits.JobMemoryLimit = limit_bytes
            checked(set_job(self.job, 9, C.byref(limits), C.sizeof(limits)))
            self.log = open(log_path, "xb", buffering=0)
            handle = msvcrt.get_osfhandle(self.log.fileno())
            os.set_handle_inheritable(handle, True)
            startup = STARTUPINFOEX()
            startup.StartupInfo.cb = C.sizeof(startup.StartupInfo)
            startup.StartupInfo.dwFlags = 0x100
            startup.StartupInfo.hStdOutput = handle
            startup.StartupInfo.hStdError = handle
            cmd = C.create_unicode_buffer(subprocess.list2cmdline(command))
            checked(
                create_process(
                    command[0],
                    cmd,
                    None,
                    None,
                    True,
                    0x08000000 | 0x4,
                    None,
                    str(cwd),
                    C.byref(startup),
                    C.byref(self.pi),
                )
            )
            os.set_handle_inheritable(handle, False)
            # The child cannot execute a single instruction before cap assignment.
            checked(assign(self.job, self.pi.hProcess))
            current = EXTENDED()
            checked(query_job(self.job, 9, C.byref(current), C.sizeof(current), None))
            assert (
                current.ProcessMemoryLimit == limit_bytes and current.JobMemoryLimit == limit_bytes
            )
            assert current.BasicLimitInformation.LimitFlags & 0x100
            assert resume(self.pi.hThread) != 0xFFFFFFFF
            self.pid = int(self.pi.dwProcessId)
        except BaseException:
            if self.pi.hProcess:
                terminate(self.pi.hProcess, 99)
                wait(self.pi.hProcess, 10000)
            self.finish()
            raise

    def poll(self):
        if wait(self.pi.hProcess, 0) == 0:
            result = W.DWORD()
            checked(exit_code(self.pi.hProcess, C.byref(result)))
            return int(result.value)
        return None

    def kill(self):
        checked(terminate(self.pi.hProcess, 98))
        wait(self.pi.hProcess, 10000)

    def memory(self):
        current = EXTENDED()
        checked(query_job(self.job, 9, C.byref(current), C.sizeof(current), None))
        return {
            "hard_process_commit_limit_bytes": int(current.ProcessMemoryLimit),
            "hard_job_commit_limit_bytes": int(current.JobMemoryLimit),
            "job_peak_process_committed_bytes": int(current.PeakProcessMemoryUsed),
            "job_peak_committed_bytes": int(current.PeakJobMemoryUsed),
        }

    def finish(self):
        if self.closed:
            return
        self.closed = True
        if self.pi.hThread:
            close(self.pi.hThread)
        if self.pi.hProcess:
            close(self.pi.hProcess)
        if self.job:
            close(self.job)
        if self.log:
            self.log.close()
