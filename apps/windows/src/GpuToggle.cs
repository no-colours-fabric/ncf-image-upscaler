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
  gpuToggle.Width=82;gpuToggle.Height=30;gpuToggle.Margin=new Thickness(0,0,8,0);gpuToggle.Visibility=Visibility.Collapsed;
  var style=new Style(typeof(ToggleButton));
  var template=new ControlTemplate(typeof(ToggleButton));
  var surface=new FrameworkElementFactory(typeof(Border));surface.SetValue(Border.CornerRadiusProperty,new CornerRadius(3));surface.SetValue(Border.BackgroundProperty,new TemplateBindingExtension(Control.BackgroundProperty));surface.SetValue(Border.BorderBrushProperty,new TemplateBindingExtension(Control.BorderBrushProperty));surface.SetValue(Border.BorderThicknessProperty,new Thickness(1));
  var text=new FrameworkElementFactory(typeof(ContentPresenter));text.SetValue(FrameworkElement.HorizontalAlignmentProperty,HorizontalAlignment.Center);text.SetValue(FrameworkElement.VerticalAlignmentProperty,VerticalAlignment.Center);surface.AppendChild(text);template.VisualTree=surface;
  foreach(var pair in new[]{new object[]{UIElement.IsMouseOverProperty,.9},new object[]{ButtonBase.IsPressedProperty,.75},new object[]{UIElement.IsEnabledProperty,.45}}){var trigger=new Trigger{Property=(DependencyProperty)pair[0],Value=(DependencyProperty)pair[0]==UIElement.IsEnabledProperty?false:true};trigger.Setters.Add(new Setter(UIElement.OpacityProperty,(double)pair[1]));template.Triggers.Add(trigger);}
  style.Setters.Add(new Setter(Control.TemplateProperty,template));gpuToggle.Style=style;gpuToggle.Click+=delegate{UpdateGpuToggle();};UpdateGpuToggle();
 }
 void SetGpuAvailable(bool available){gpuAvailable=available;gpuChecking=false;gpuToggle.Visibility=available?Visibility.Visible:Visibility.Collapsed;gpuToggle.IsChecked=available;UpdateGpuToggle();}
 void UpdateGpuToggle(){bool on=gpuAvailable&&gpuToggle.IsChecked==true;gpuToggle.Content=on?"GPU On":"GPU Off";gpuToggle.Background=on?SystemColors.HighlightBrush:SystemColors.ControlBrush;gpuToggle.Foreground=on?SystemColors.HighlightTextBrush:SystemColors.ControlTextBrush;gpuToggle.BorderBrush=on?SystemColors.HighlightBrush:SystemColors.ActiveBorderBrush;gpuToggle.ToolTip=on?"Use GPU (DirectML), with CPU fallback if needed":"Use CPU";System.Windows.Automation.AutomationProperties.SetName(gpuToggle,Convert.ToString(gpuToggle.Content));}
 async Task DetectGpu(){
  bool available=await Task.Factory.StartNew(()=>{
   var info=new ProcessStartInfo(Path.Combine(bundle,"runtime","python.exe"),Quote(Path.Combine(bundle,"engine","gpu_capability.py"))+" "+Quote(session)){UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true,WorkingDirectory=bundle};info.EnvironmentVariables["PYTHONDONTWRITEBYTECODE"]="1";
   try{using(var process=Process.Start(info)){var output=Task.Factory.StartNew(()=>process.StandardOutput.ReadToEnd());var errors=Task.Factory.StartNew(()=>process.StandardError.ReadToEnd());if(!process.WaitForExit(15000)){process.Kill();process.WaitForExit();return false;}var data=new JavaScriptSerializer().Deserialize<System.Collections.Generic.Dictionary<string,object>>(output.Result.Trim());return process.ExitCode==0&&data.ContainsKey("available")&&Convert.ToBoolean(data["available"]);}}catch{return false;}
  });
  if(windowClosed)return;SetGpuAvailable(available);Refresh();
 }
}
}
