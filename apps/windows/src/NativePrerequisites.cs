using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

namespace NCF {
public sealed class PrerequisiteResult {
 public int Code;public string Message;public Version Version;
}
public static class NativePrerequisites {
 public const string DownloadPage="https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist";
 public static PrerequisiteResult Evaluate(bool exists,Version version,bool loaded) {
  if(!exists)return new PrerequisiteResult{Code=10,Message="Microsoft Visual C++ 2015–2022 Redistributable (x64) is required."};
  if(version==null||version.Major<14||version.Major==14&&version.Minor<29)return new PrerequisiteResult{Code=11,Message="The Microsoft Visual C++ x64 Runtime is too old. Version 14.29 or newer is required."};
  if(!loaded)return new PrerequisiteResult{Code=12,Message="The Microsoft Visual C++ x64 Runtime could not be loaded. Repair it using Microsoft's installer."};
  return new PrerequisiteResult{Code=0,Message="Microsoft Visual C++ x64 Runtime is ready.",Version=version};
 }
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)]static extern IntPtr LoadLibraryEx(string path,IntPtr file,uint flags);
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode)]static extern uint GetModuleFileName(IntPtr module,StringBuilder path,int length);
 [DllImport("kernel32.dll")]static extern bool FreeLibrary(IntPtr module);
 [DllImport("kernel32.dll",CharSet=CharSet.Ansi,ExactSpelling=true)]static extern IntPtr GetProcAddress(IntPtr module,string name);
 public static PrerequisiteResult Check() {
  // System prerequisite, NOT an app-local closure claim. No System32 copying.
  string path=Path.Combine(Environment.SystemDirectory,"msvcp140.dll");
  if(!File.Exists(path))return Evaluate(false,null,false);
  Version version=null;try{var info=FileVersionInfo.GetVersionInfo(path);version=new Version(info.FileMajorPart,info.FileMinorPart,info.FileBuildPart,info.FilePrivatePart);}catch{return Evaluate(true,null,false);}
  var initial=Evaluate(true,version,true);if(initial.Code!=0)return initial;
  IntPtr module=LoadLibraryEx(path,IntPtr.Zero,0x100|0x800);
  if(module==IntPtr.Zero)return Evaluate(true,version,false);
  try{var actual=new StringBuilder(32768);bool loaded=GetModuleFileName(module,actual,actual.Capacity)>0&&String.Equals(Path.GetFullPath(actual.ToString()),Path.GetFullPath(path),StringComparison.OrdinalIgnoreCase);foreach(string name in RequiredMsvcExports.Names)if(GetProcAddress(module,name)==IntPtr.Zero)loaded=false;return Evaluate(true,version,loaded);}
  finally{FreeLibrary(module);}
 }
 public static string Guidance(PrerequisiteResult result){return result.Message+"\n\nGet or repair this component from Microsoft:\n"+DownloadPage+"\n\nInstalling a missing system prerequisite may require administrator permission. The app itself installs for the current user. No Python installation is needed.";}
}
}
