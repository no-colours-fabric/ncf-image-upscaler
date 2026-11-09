using System;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
namespace NCF {
public sealed partial class MainWindow {
 readonly ToggleButton gpuToggle=new ToggleButton();
 bool gpuAvailable,gpuChecking=true;
 string GpuBackend {get{return gpuAvailable&&gpuToggle.IsChecked==true?"auto":"cpu";}}
 void InitializeGpuToggle(){
  gpuToggle.Width=74;gpuToggle.Height=24;gpuToggle.Margin=new Thickness(0,0,6,0);gpuToggle.Visibility=Visibility.Collapsed;gpuToggle.Click+=delegate{UpdateGpuToggle();};UpdateGpuToggle();
 }
 void SetGpuAvailable(bool available){gpuAvailable=available;gpuChecking=false;gpuToggle.Visibility=available?Visibility.Visible:Visibility.Collapsed;gpuToggle.IsChecked=available;UpdateGpuToggle();}
 void UpdateGpuToggle(){bool on=gpuAvailable&&gpuToggle.IsChecked==true;gpuToggle.Content=on?"GPU On":"GPU Off";StyleGpuToggle();gpuToggle.ToolTip=on?"Use GPU (DirectML), with CPU fallback if needed":"Use CPU";System.Windows.Automation.AutomationProperties.SetName(gpuToggle,Convert.ToString(gpuToggle.Content));}
 readonly object gpuProbeGate=new object();Process gpuProbeProcess;bool gpuProbeStopped;
#if CLOSE_REGRESSION
 public Func<Task<bool>> GpuCapabilityOverride;
#endif
 void StopGpuProbe(){lock(gpuProbeGate){gpuProbeStopped=true;if(gpuProbeProcess!=null)try{if(!gpuProbeProcess.HasExited)gpuProbeProcess.Kill();}catch{}}}
 async void BeginGpuDetection(){try{await DetectGpu();}catch{if(!windowClosed){SetGpuAvailable(false);Refresh();}}}
 async Task DetectGpu(){
  bool available;
#if CLOSE_REGRESSION
  if(GpuCapabilityOverride!=null)available=await GpuCapabilityOverride();else
#endif
  available=await Task.Factory.StartNew(()=>{
   var info=new ProcessStartInfo(Path.Combine(bundle,"runtime","python.exe"),Quote(Path.Combine(bundle,"engine","gpu_capability.py"))+" "+Quote(session)){UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true,WorkingDirectory=bundle};info.EnvironmentVariables["PYTHONDONTWRITEBYTECODE"]="1";
   try{using(var process=new Process{StartInfo=info}){try{
    lock(gpuProbeGate){if(gpuProbeStopped)return false;process.Start();gpuProbeProcess=process;}
    var output=Task.Factory.StartNew(()=>process.StandardOutput.ReadToEnd());var errors=Task.Factory.StartNew(()=>process.StandardError.ReadToEnd());
    if(!process.WaitForExit(15000)){process.Kill();process.WaitForExit();return false;}
    var data=new JavaScriptSerializer().Deserialize<System.Collections.Generic.Dictionary<string,object>>(output.Result.Trim());return process.ExitCode==0&&data.ContainsKey("available")&&Convert.ToBoolean(data["available"]);
   }finally{lock(gpuProbeGate){if(gpuProbeProcess==process)gpuProbeProcess=null;}}}}catch{return false;}
  });
  if(windowClosed)return;SetGpuAvailable(available);Refresh();
 }
}
}
