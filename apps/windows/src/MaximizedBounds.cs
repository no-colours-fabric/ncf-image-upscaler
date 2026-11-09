using System;
using System.Runtime.InteropServices;
namespace NCF {
// Win32 monitor/work rectangles are physical virtual-screen pixels, not WPF DIPs.
public static class MaximizedBounds {
 [StructLayout(LayoutKind.Sequential)]public struct Point {public int X,Y;}
 [StructLayout(LayoutKind.Sequential)]public struct Rect {public int Left,Top,Right,Bottom;}
 [StructLayout(LayoutKind.Sequential)]public struct MinMaxInfo {public Point Reserved,MaxSize,MaxPosition,MinTrackSize,MaxTrackSize;}
 [StructLayout(LayoutKind.Sequential)]public struct MonitorInfo {public int Size;public Rect Monitor,Work;public uint Flags;}
 [DllImport("user32.dll")]static extern IntPtr MonitorFromWindow(IntPtr hwnd,uint flags);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern bool GetMonitorInfo(IntPtr monitor,ref MonitorInfo info);
 public static bool TryGetMonitor(IntPtr window,out MonitorInfo info){info=new MonitorInfo{Size=Marshal.SizeOf(typeof(MonitorInfo))};var monitor=MonitorFromWindow(window,2);return monitor!=IntPtr.Zero&&GetMonitorInfo(monitor,ref info);}
 public static MinMaxInfo Calculate(MinMaxInfo defaults,Rect monitor,Rect work){
  if(work.Right<=work.Left||work.Bottom<=work.Top)return defaults;
  defaults.MaxPosition=new Point{X=work.Left-monitor.Left,Y=work.Top-monitor.Top};
  defaults.MaxSize=new Point{X=work.Right-work.Left,Y=work.Bottom-work.Top};
  return defaults;
 }
 public static bool Handle(IntPtr window,IntPtr pointer){MonitorInfo info;if(pointer==IntPtr.Zero||!TryGetMonitor(window,out info))return false;var limits=(MinMaxInfo)Marshal.PtrToStructure(pointer,typeof(MinMaxInfo));limits=Calculate(limits,info.Monitor,info.Work);Marshal.StructureToPtr(limits,pointer,false);return true;}
}
}
