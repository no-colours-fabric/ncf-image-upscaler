using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;

namespace NCF {
public sealed partial class MainWindow : Window {
    readonly string bundle=AppDomain.CurrentDomain.BaseDirectory;
    readonly string session;
    readonly TemporarySession ownedSession;
    readonly ImageCanvas canvas=new ImageCanvas();
    readonly FolderSidebar sidebar=new FolderSidebar();
    readonly Grid imageArea=new Grid();
    readonly System.Windows.Controls.Primitives.ToggleButton[] scales=new System.Windows.Controls.Primitives.ToggleButton[3];
    BrowserSession browser;
    ImageDocument document,jobDocument;
    int loadGeneration;
    bool switching;
    static bool quitting;
    static readonly Dictionary<string,MainWindow> windows=new Dictionary<string,MainWindow>(StringComparer.OrdinalIgnoreCase);
    static bool NativeControlFocus(){DependencyObject focus=Keyboard.FocusedElement as DependencyObject;while(focus!=null){if(focus is System.Windows.Controls.Primitives.TextBoxBase||focus is System.Windows.Controls.Primitives.ButtonBase||focus is System.Windows.Controls.Primitives.Selector||focus is Slider)return true;focus=focus is Visual?VisualTreeHelper.GetParent(focus):LogicalTreeHelper.GetParent(focus);}return false;}
    protected override void OnSourceInitialized(EventArgs args){base.OnSourceInitialized(args);var host=System.Windows.Interop.HwndSource.FromHwnd(new System.Windows.Interop.WindowInteropHelper(this).Handle);host.AddHook(delegate(IntPtr hwnd,int message,IntPtr wparam,IntPtr lparam,ref bool handled){if(message==0x100&&IsActive&&!NativeControlFocus()&&(Keyboard.Modifiers& (ModifierKeys.Control|ModifierKeys.Alt|ModifierKeys.Windows))==0){int scan=(int)((lparam.ToInt64()>>16)&255);Key key=scan==0x2c?Key.Z:scan==0x2d?Key.X:scan==0x39?Key.Space:scan==1?Key.Escape:Key.None;if(key!=Key.None){var e=new KeyEventArgs(Keyboard.PrimaryDevice,host,Environment.TickCount,key){RoutedEvent=Keyboard.PreviewKeyDownEvent};HandleNavigation(e);handled=e.Handled;}}return IntPtr.Zero;});}
    readonly Button open=new Button(),enhance=new Button(),cancel=new Button(),save=new Button(),saveAs=new Button();
    readonly ComboBox model=new ComboBox(),scale=new ComboBox(),view=new ComboBox();
    readonly TextBlock status=new TextBlock(),filename=new TextBlock(),zoomLabel=new TextBlock(),elapsed=new TextBlock();
    readonly ProgressBar progress=new ProgressBar();
    readonly DispatcherTimer timer=new DispatcherTimer();
    readonly Stopwatch watch=new Stopwatch();
    readonly ProcessingProgress processing=new ProcessingProgress();
    int jobGeneration;
    string lastJobNote="";
    string sourcePath,resultPath,savedPath;
    bool busy,loading,dirty,cancelRequested,closeWhenDone,allowClose,closingFlow;
    bool closeScheduled,commitCloseScheduled;
#if CLOSE_REGRESSION
    public Func<string,string,string[],int> DecisionOverride;
    public Func<bool,Task<bool>> SaveOverride;
    public Action<string> ErrorOverride;
    public Func<string,string,string> InputOverride;
    public Func<string,BitmapSource> ViewerLoaderOverride;
    public Func<string,BitmapSource> ThumbnailLoaderOverride;
    public void SetTestState(string original,string result,bool working) {sourcePath=original;resultPath=result;dirty=true;busy=working;}
    public bool TestDirty {get{return dirty;}}
    public bool TestBusy {get{return busy;}}
    public bool TestCancelRequested {get{return cancelRequested;}}
    public async Task CompleteTestWork() {busy=false;if(closeWhenDone)await FinishClose();}
    public void ForceTestClose() {allowClose=true;Close();}
#endif
    int resultScale=4;
    Process worker;
    public MainWindow(string initial) {
        Title="NCF Image Upscaler";Width=1296;Height=839;MinWidth=1056;MinHeight=579;WindowStartupLocation=WindowStartupLocation.CenterScreen;
        Background=Brushes.WhiteSmoke;FontFamily=new FontFamily("Segoe UI");FontSize=13;
        TemporarySession.RemoveAbandoned(TemporarySession.DefaultRoot);ownedSession=new TemporarySession(TemporarySession.DefaultRoot);session=ownedSession.DirectoryPath;sidebar.MetadataLoader=(paths,stop)=>MetadataReader.Read(bundle,session,paths,stop);
        var root=new DockPanel{Background=Brushes.WhiteSmoke};Content=root;
        var toolbar=new Grid{Margin=new Thickness(12,8,12,8)};DockPanel.SetDock(toolbar,Dock.Top);root.Children.Add(toolbar);
        for(int i=0;i<10;i++)toolbar.ColumnDefinitions.Add(new ColumnDefinition{Width=i==1||i==5?new GridLength(1,GridUnitType.Star):GridLength.Auto});
        Configure(open,"Open",async delegate{await OpenDialog();});SvgIcons.Button(open,"folder-open","Open",18);toolbar.Children.Add(open);
        var modelsButton=new Button();Configure(modelsButton,"Models…",delegate{new ModelsWindow(this).ShowDialog();});Grid.SetColumn(modelsButton,1);modelsButton.HorizontalAlignment=HorizontalAlignment.Left;toolbar.Children.Add(modelsButton);
        model.ItemsSource=new[]{"Photo","Illustration","Fast"};model.SelectedIndex=0;model.Width=138;model.Height=30;model.Margin=new Thickness(0,0,8,0);model.VerticalContentAlignment=VerticalAlignment.Center;Grid.SetColumn(model,2);toolbar.Children.Add(model);
        scale.ItemsSource=new[]{"×1","×2","×4"};scale.SelectedIndex=2;
        var segments=new UniformGrid{Rows=1,Columns=3,Width=118,Height=30,Margin=new Thickness(0,0,8,0)};Grid.SetColumn(segments,3);toolbar.Children.Add(segments);
        for(int i=0;i<3;i++){int index=i;var button=new System.Windows.Controls.Primitives.ToggleButton{Content=new[]{"×1","×2","×4"}[i],IsChecked=i==2,BorderThickness=new Thickness(.5),Padding=new Thickness(2)};scales[i]=button;segments.Children.Add(button);button.Click+=delegate{scale.SelectedIndex=index;for(int k=0;k<3;k++)scales[k].IsChecked=k==index;};}
        Configure(enhance,"Enhance",async delegate{await Enhance();});SvgIcons.Button(enhance,"sparkles","Enhance",18);Grid.SetColumn(enhance,4);toolbar.Children.Add(enhance);
        zoomLabel.Width=65;zoomLabel.TextAlignment=TextAlignment.Center;zoomLabel.VerticalAlignment=VerticalAlignment.Center;zoomLabel.ToolTip="Zoom — 100% uses result pixels";Grid.SetColumn(zoomLabel,6);toolbar.Children.Add(zoomLabel);
        var fit=new Button();Configure(fit,"Fit",delegate{canvas.Fit();});SvgIcons.Button(fit,"maximize-2","Fit",18);Grid.SetColumn(fit,7);toolbar.Children.Add(fit);
        Configure(save,"Save",async delegate{await SaveResult(false);});SvgIcons.Button(save,"download","Save",18);Grid.SetColumn(save,8);toolbar.Children.Add(save);
        Configure(saveAs,"Save As…",async delegate{await SaveResult(true);});SvgIcons.Button(saveAs,"folder-down","Save As…",18);Grid.SetColumn(saveAs,9);toolbar.Children.Add(saveAs);
        var footer=new DockPanel{Height=34,Margin=new Thickness(16,0,16,0)};DockPanel.SetDock(footer,Dock.Bottom);root.Children.Add(footer);
        var hint=new TextBlock{Text="Z / X, Space — navigate · Scroll — zoom · Esc — close window",Foreground=Brushes.DarkGray,VerticalAlignment=VerticalAlignment.Center,Margin=new Thickness(12,0,0,0)};DockPanel.SetDock(hint,Dock.Right);footer.Children.Add(hint);
        Configure(cancel,"×",delegate{CancelWorker();});cancel.Padding=new Thickness(4,0,4,0);cancel.MinHeight=22;SvgIcons.Button(cancel,"x","",16);cancel.Style=SvgIcons.IconButtonStyle(11);cancel.Width=22;cancel.ToolTip="Cancel enhancement";System.Windows.Automation.AutomationProperties.SetName(cancel,"Cancel enhancement");cancel.BorderThickness=new Thickness(0);cancel.Background=Brushes.Transparent;DockPanel.SetDock(cancel,Dock.Right);footer.Children.Add(cancel);
        progress.Width=150;progress.Height=5;progress.Margin=new Thickness(12,0,8,0);progress.Visibility=Visibility.Collapsed;DockPanel.SetDock(progress,Dock.Right);footer.Children.Add(progress);status.VerticalAlignment=VerticalAlignment.Center;status.TextTrimming=TextTrimming.CharacterEllipsis;footer.Children.Add(status);
        root.Children.Add(imageArea);imageArea.Children.Add(canvas);imageArea.Children.Add(sidebar);sidebar.SetBackdrop(canvas);canvas.ZoomChanged=delegate{zoomLabel.Text=Math.Round(canvas.Percent)+"%";};
        sidebar.ObstructionChanged=value=>canvas.LeadingObstruction=value;sidebar.OpenDocument=async d=>await ShowDocument(d);sidebar.SelectionChanged=delegate{SyncDocumentState();UpdateStatus();};sidebar.FolderRefreshed=OnFolderRefreshed;sidebar.Navigation=HandleNavigation;imageArea.SizeChanged+=delegate{sidebar.UpdateSize();};
        model.SelectionChanged+=delegate{if(!switching&&document!=null)document.Preset=Convert.ToString(model.SelectedItem);};scale.SelectionChanged+=delegate{for(int k=0;k<3;k++)scales[k].IsChecked=k==scale.SelectedIndex;if(!switching&&document!=null)document.Scale=new[]{1,2,4}[scale.SelectedIndex];};
        timer.Interval=TimeSpan.FromSeconds(1);timer.Tick+=delegate{if(cancelRequested&&worker!=null&&cancelSince.Elapsed.TotalSeconds>5){try{if(!worker.HasExited)worker.Kill();}catch{}}UpdateStatus();sidebar.Surface.InvalidateVisual();};
        AllowDrop=true;DragOver+=delegate(object sender,DragEventArgs e){e.Effects=e.Data.GetDataPresent(DataFormats.FileDrop)?DragDropEffects.Copy:DragDropEffects.None;e.Handled=true;};
        Drop+=async delegate(object sender,DragEventArgs e){var paths=e.Data.GetData(DataFormats.FileDrop) as string[];if(paths!=null&&paths.Length>0)await OpenPath(paths[0]);e.Handled=true;};
        PreviewKeyDown+=async delegate(object sender,KeyEventArgs e){
            if(Keyboard.Modifiers==ModifierKeys.Control&&e.Key==Key.O){e.Handled=true;await OpenDialog();}
            else if((Keyboard.Modifiers&ModifierKeys.Control)!=0&&e.Key==Key.S){e.Handled=true;await SaveResult((Keyboard.Modifiers&ModifierKeys.Shift)!=0);}
            else if(Keyboard.Modifiers==ModifierKeys.Control&&e.Key==Key.U){e.Handled=true;await Enhance();}
            else if(Keyboard.Modifiers==ModifierKeys.Control&&e.Key==Key.W){Close();e.Handled=true;}
            else if(Keyboard.Modifiers==ModifierKeys.Control&&e.Key==Key.D0){canvas.Fit();e.Handled=true;}
            else if(Keyboard.Modifiers==ModifierKeys.Control&&e.Key==Key.D1){canvas.ActualPixels();e.Handled=true;}
            else if(Keyboard.Modifiers==ModifierKeys.Control&&(e.Key==Key.OemPlus||e.Key==Key.Add)){canvas.ZoomBy(1.25);e.Handled=true;}
            else if(Keyboard.Modifiers==ModifierKeys.Control&&(e.Key==Key.OemMinus||e.Key==Key.Subtract)){canvas.ZoomBy(.8);e.Handled=true;}
            else if(!NativeControlFocus())HandleNavigation(e);
        };
        Closing+=OnClosing;Closed+=delegate{loadGeneration++;sidebar.Dispose();if(browser!=null){windows.Remove(browser.Folder);browser.Dispose();}ownedSession.Dispose();};
        InstallFileActions();Loaded+=async delegate{Refresh();if(!String.IsNullOrEmpty(initial))await OpenPath(initial);};Refresh();
    }
    void StoreDocument(){if(document==null)return;document.Preset=Convert.ToString(model.SelectedItem);document.Scale=new[]{1,2,4}[scale.SelectedIndex];if(canvas.Original!=null)document.Position=canvas.Position;}
    void UpdateStatus(){if(browser==null){status.Text="Open an image or drag it into the window";return;}if(busy){status.Text=(cancelRequested?"Cancelling":processing.Stage)+" · "+(cancelRequested?"Waiting for worker exit":processing.Detail)+" · "+ProcessingProgress.Elapsed(watch.Elapsed)+" elapsed · "+Path.GetFileName(jobDocument==null?sourcePath:jobDocument.Path);return;}var list=browser.Visible();int index=list.IndexOf(document);status.Text=(index<0?"Outside filter · Matches: "+list.Count:(index+1)+" of "+list.Count)+(canvas.Original==null?"":" · "+canvas.Original.PixelWidth+" × "+canvas.Original.PixelHeight)+(sidebar.Selected.Count>1?" · "+sidebar.Selected.Count+" selected":"")+(document!=null&&document.Missing?" · Original unavailable":"")+(canvas.HasAlpha?" · Transparency":"")+(dirty?" · Unsaved ×"+resultScale:savedPath!=null?" · "+Path.GetFileName(savedPath):"")+(document==jobDocument&&lastJobNote.Length>0?" · "+lastJobNote:"");sidebar.Surface.InvalidateVisual();}
    void HandleNavigation(KeyEventArgs e){
        if(e.Handled)return;bool endpoint=Keyboard.Modifiers==ModifierKeys.Control&&(e.Key==Key.Home||e.Key==Key.End);if(!endpoint&&Keyboard.Modifiers!=ModifierKeys.None&&Keyboard.Modifiers!=ModifierKeys.Shift)return;
        if(e.Key==Key.Escape){e.Handled=true;Close();return;}
        if(browser==null)return;var items=browser.Visible();if(items.Count==0)return;int old=items.IndexOf(browser.Current),next=old;bool shift=(Keyboard.Modifiers&ModifierKeys.Shift)!=0;
        if(e.Key==Key.Z)next=old<0?items.Count-1:Math.Max(0,old-1);else if(e.Key==Key.X||e.Key==Key.Space)next=old<0?0:Math.Min(items.Count-1,old+1);else if(e.Key==Key.Home)next=0;else if(e.Key==Key.End)next=items.Count-1;
        else if(e.Key==Key.PageDown||e.Key==Key.PageUp){bool down=e.Key==Key.PageDown;double height=Math.Max(1,sidebar.Scroll.ViewportHeight-40);next=BrowserNavigation.Page(old,sidebar.Surface.Frames,height,down);sidebar.Scroll.ScrollToVerticalOffset(sidebar.Scroll.VerticalOffset+(down?height:-height));}
        else if(sidebar.Surface.IsKeyboardFocusWithin&&(e.Key==Key.Right||e.Key==Key.Down||e.Key==Key.Left||e.Key==Key.Up))next=BrowserNavigation.Arrow(old,sidebar.Surface.Frames,e.Key);else return;
        e.Handled=true;sidebar.Select(items[next],shift?ModifierKeys.Shift:ModifierKeys.None,false);sidebar.LocateForNavigation(items[next]);
    }
    readonly Stopwatch cancelSince=new Stopwatch();
    async void QuitAll(){if(quitting)return;quitting=true;var all=Application.Current.Windows.OfType<MainWindow>().ToArray();try{foreach(var window in all){window.closeWhenDone=true;if(window.busy)window.CancelWorker();}while(all.Any(w=>w.busy||w.loading||w.fileWork))await Task.Delay(50);foreach(var window in all){await window.FinishClose();if(!window.commitCloseScheduled){foreach(var w in all)w.closeWhenDone=false;break;}await Task.Delay(1);}}finally{quitting=false;}}
    static TextBlock Label(string text) {return new TextBlock {Text=text,VerticalAlignment=VerticalAlignment.Center,Margin=new Thickness(7,0,1,0),Foreground=new SolidColorBrush(Color.FromRgb(77,89,106))};}
    static void Configure(Button b,string text,RoutedEventHandler action) {b.Content=text;b.Padding=new Thickness(14,6,14,6);b.Margin=new Thickness(0,0,7,0);b.MinHeight=31;b.Click+=action;}
    void Refresh(){open.IsEnabled=!loading;enhance.IsEnabled=sourcePath!=null&&canvas.Original!=null&&File.Exists(sourcePath)&&!busy&&!loading&&!canvas.IsLoading&&!closingFlow&&!closeWhenDone;model.IsEnabled=scale.IsEnabled=!loading;foreach(var b in scales)if(b!=null)b.IsEnabled=!loading;cancel.IsEnabled=busy&&!cancelRequested;cancel.Visibility=busy?Visibility.Visible:Visibility.Collapsed;save.IsEnabled=saveAs.IsEnabled=resultPath!=null&&!loading&&!canvas.IsLoading&&!closingFlow&&!(busy&&document==jobDocument);Title="NCF Image Upscaler"+(sourcePath==null?"":" — "+Path.GetFileName(sourcePath))+(dirty?" • Unsaved":"");UpdateStatus();}
    public static BitmapSource LoadBitmap(string path) {
        BitmapSource image;using(var input=new FileStream(Path.GetFullPath(path),FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete))image=BitmapFrame.Create(input,BitmapCreateOptions.PreservePixelFormat,BitmapCacheOption.OnLoad);
        var frame=image as BitmapFrame;int orientation=1;
        try {var metadata=frame.Metadata as BitmapMetadata;if(metadata!=null){object value=null;if(metadata.ContainsQuery("/app1/ifd/{ushort=274}"))value=metadata.GetQuery("/app1/ifd/{ushort=274}");else if(metadata.ContainsQuery("/ifd/{ushort=274}"))value=metadata.GetQuery("/ifd/{ushort=274}");if(value!=null)orientation=Convert.ToInt32(value);}}catch{}
        var transforms=new TransformGroup();
        if(orientation==2)transforms.Children.Add(new ScaleTransform(-1,1));
        if(orientation==3)transforms.Children.Add(new RotateTransform(180));
        if(orientation==4)transforms.Children.Add(new ScaleTransform(1,-1));
        if(orientation==5){transforms.Children.Add(new ScaleTransform(-1,1));transforms.Children.Add(new RotateTransform(270));}
        if(orientation==6)transforms.Children.Add(new RotateTransform(90));
        if(orientation==7){transforms.Children.Add(new ScaleTransform(-1,1));transforms.Children.Add(new RotateTransform(90));}
        if(orientation==8)transforms.Children.Add(new RotateTransform(270));
        if(transforms.Children.Count>0)image=new TransformedBitmap(image,transforms);
        image.Freeze();return image;
    }
    async Task OpenDialog(){if(loading)return;var dialog=new OpenFileDialog{Title="Open images",Filter="Images|*.png;*.jpg;*.jpeg;*.bmp;*.tif;*.tiff;*.webp|All files|*.*",CheckFileExists=true,Multiselect=true};if(dialog.ShowDialog(this)==true)foreach(var path in dialog.FileNames)await OpenPath(path);}
    BitmapSource LoadAsset(string path){if(!String.Equals(Path.GetExtension(path),".webp",StringComparison.OrdinalIgnoreCase))return LoadBitmap(path);string output=Path.Combine(session,"preview-"+Guid.NewGuid().ToString("N")+".png");var info=new ProcessStartInfo(Path.Combine(bundle,"runtime","python.exe"),Quote(Path.Combine(bundle,"engine","asset.py"))+" "+Quote(path)+" "+Quote(output)){UseShellExecute=false,CreateNoWindow=true,RedirectStandardError=true,WorkingDirectory=bundle};using(var p=Process.Start(info)){string error=p.StandardError.ReadToEnd();p.WaitForExit();if(p.ExitCode!=0)throw new IOException("Could not decode WebP: "+error);}try{return LoadBitmap(output);}finally{File.Delete(output);}}
    async Task OpenPath(string path){if(loading||closingFlow||closeWhenDone||allowClose)return;
        path=Path.GetFullPath(path);string folder=Directory.Exists(path)?path:Path.GetDirectoryName(path);MainWindow existing;
        if(windows.TryGetValue(folder,out existing)&&existing!=this){existing.Activate();if(File.Exists(path))await existing.OpenPath(path);return;}
        if(browser!=null&&!String.Equals(folder,browser.Folder,StringComparison.OrdinalIgnoreCase)){new MainWindow(path).Show();return;}
        try{if(browser==null){browser=new BrowserSession(folder);windows[folder]=this;sidebar.Attach(browser,session,LoadThumbnail,ownedSession);}browser.Refresh();var d=browser.Documents.FirstOrDefault(x=>String.Equals(x.Path,path,StringComparison.OrdinalIgnoreCase))??browser.Visible().FirstOrDefault();if(d!=null){sidebar.Selected.Clear();sidebar.Selected.Add(d);await ShowDocument(d);sidebar.Locate();}}
        catch(Exception e){ShowError("Could not open this image or folder.\n\n"+e.Message);}
    }
    BitmapSource LoadForViewer(string path){
#if CLOSE_REGRESSION
        if(ViewerLoaderOverride!=null)return ViewerLoaderOverride(path);
#endif
        return LoadAsset(path);
    }
    BitmapSource LoadThumbnail(string path){
#if CLOSE_REGRESSION
        if(ThumbnailLoaderOverride!=null)return ThumbnailLoaderOverride(path);
#endif
        return LoadAsset(path);
    }
    async Task<bool> ResolveUnsaved() {
        if(!dirty)return true;
        int choice=Choice("Unsaved enhancement","Save the enhanced image before continuing?",new string[]{"Save","Discard Result","Cancel"});
        if(choice==0)return await SaveResult(false);if(choice==1){string old=resultPath;resultPath=savedPath=null;dirty=false;if(document!=null){document.Result=document.Saved=null;}try{if(old!=null)File.Delete(old);}catch{}return true;}return false;
    }
    async Task Enhance() {
        if(busy||loading||canvas.IsLoading||closingFlow||closeWhenDone||sourcePath==null||canvas.Original==null||!File.Exists(sourcePath))return;
        string chosenPreset=Convert.ToString(model.SelectedItem).ToLowerInvariant();int chosenScale=new int[]{1,2,4}[scale.SelectedIndex];if(!ModelStore.Present(ModelStore.Select(chosenPreset,chosenScale))){ShowError("This model is not prepared. Open Models, choose Download / Repair Models, then try Enhance again. Processing never downloads models.");return;}
        if(dirty && Choice("Enhance again?","The current result will remain available if the new enhancement fails.",new string[]{"Enhance Again","Cancel"})!=0)return;
        StoreDocument();jobDocument=document;string input=sourcePath;
        string requested=Path.Combine(session,"result-"+Guid.NewGuid().ToString("N")+".png");
        string preset=Convert.ToString(model.SelectedItem).ToLowerInvariant();int requestedScale=new int[]{1,2,4}[scale.SelectedIndex];
        if(jobDocument!=null){jobDocument.Processing=true;jobDocument.WorkState="Preparing";}
        jobGeneration++;lastJobNote="";processing.Reset();busy=true;cancelRequested=false;watch.Restart();cancelSince.Reset();timer.Start();progress.IsIndeterminate=true;progress.Visibility=Visibility.Visible;status.Text="Preparing local CPU processing…";Refresh();
        Outcome outcome=null;
        try {
            outcome=await Task.Factory.StartNew(()=>RunWorker(new string[]{"--input",input,"--output",requested,"--model",preset,"--scale",requestedScale.ToString()}));
            if(outcome.Completed!=null && File.Exists(requested)) {
                var bitmap=await Task.Factory.StartNew(()=>LoadBitmap(requested));
                if(jobDocument!=null){string old=jobDocument.Result;jobDocument.Result=requested;jobDocument.Saved=null;jobDocument.ResultScale=requestedScale;if(old!=null&&old!=requested)try{File.Delete(old);}catch{}}
                if(document==jobDocument){resultPath=requested;savedPath=null;resultScale=requestedScale;dirty=true;canvas.SetResult(bitmap);displayedResult=requested;}
                double seconds=Convert.ToDouble(outcome.Completed["seconds"]);lastJobNote="Completed in "+seconds.ToString("0.0",System.Globalization.CultureInfo.InvariantCulture)+" s";
                status.Text="Enhanced to "+bitmap.PixelWidth+" × "+bitmap.PixelHeight+" in "+seconds.ToString("0.0",System.Globalization.CultureInfo.InvariantCulture)+" s · Not saved";
            } else if(cancelRequested || outcome.Cancelled){lastJobNote="Cancelled · Previous result retained";status.Text=lastJobNote;}
            else {lastJobNote="Processing failed · Previous result retained";status.Text=lastJobNote;ShowError(outcome.Error??"The worker ended without a complete image result.");}
        }catch(Exception e){lastJobNote="Processing failed · Previous result retained";status.Text=lastJobNote;ShowError(e.Message);}
        finally {if(jobDocument!=null){jobDocument.Processing=false;jobDocument.WorkState="";}worker=null;busy=false;timer.Stop();watch.Stop();progress.Visibility=Visibility.Collapsed;elapsed.Text="Elapsed "+watch.Elapsed.ToString(@"mm\:ss");Refresh();}
        if(closeWhenDone)await FinishClose();
    }
    sealed class Outcome {public Dictionary<string,object> Completed;public bool Cancelled;public string Error;}
    Outcome RunWorker(string[] arguments) {
        int generation=jobGeneration;var info=new ProcessStartInfo(Path.Combine(bundle,"runtime","python.exe"));
        info.Arguments=String.Join(" ",new string[]{Path.Combine(bundle,"engine","launcher.py")}.Concat(arguments).Select(Quote));
        info.WorkingDirectory=bundle;info.UseShellExecute=false;info.CreateNoWindow=true;info.RedirectStandardOutput=true;info.RedirectStandardError=true;info.RedirectStandardInput=true;
        info.StandardOutputEncoding=Encoding.UTF8;info.StandardErrorEncoding=Encoding.UTF8;info.EnvironmentVariables["PYTHONIOENCODING"]="utf-8";info.EnvironmentVariables["PYTHONDONTWRITEBYTECODE"]="1";
        var outcome=new Outcome();
        using(var process=new Process {StartInfo=info}) {
            worker=process;process.Start();var errors=Task.Factory.StartNew(()=>process.StandardError.ReadToEnd());string line;
            while((line=process.StandardOutput.ReadLine())!=null) {
                Dictionary<string,object> data;
                try {data=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(line);}catch{continue;}
                string kind=data.ContainsKey("event")?Convert.ToString(data["event"]):"";
                if(kind=="completed")outcome.Completed=data;
                if(kind=="cancelled")outcome.Cancelled=true;
                if(kind=="error")outcome.Error=Convert.ToString(data["message"]);
                Dispatcher.BeginInvoke(new Action(()=>{if(generation==jobGeneration&&!allowClose)ProgressEvent(data);}));
            }
            process.WaitForExit();string diagnostics=errors.Result;
            if(process.ExitCode!=0 && outcome.Error==null && !outcome.Cancelled && !cancelRequested)outcome.Error="The image worker stopped unexpectedly.\n"+diagnostics.Substring(Math.Max(0,diagnostics.Length-700));
        }
        return outcome;
    }
    void ProgressEvent(Dictionary<string,object> data) {
        if(!busy||cancelRequested)return;
        processing.Apply(data);
        progress.IsIndeterminate=!processing.Determinate;progress.Minimum=0;progress.Maximum=Math.Max(1,processing.Total);progress.Value=Math.Min(progress.Maximum,processing.Completed);
        if(jobDocument!=null){jobDocument.WorkState=processing.Stage=="Enhancing"&&!processing.FullFrame?processing.Percent+"%":processing.Stage;jobDocument.WorkProgress=processing.Total>0?(double)processing.Completed/processing.Total:0;}
        System.Windows.Automation.AutomationProperties.SetName(progress,processing.Stage+" "+processing.Detail);
        UpdateStatus();sidebar.Surface.InvalidateVisual();
    }    void CancelWorker() {if(!busy||cancelRequested)return;cancelRequested=true;cancelSince.Restart();progress.IsIndeterminate=true;if(jobDocument!=null)jobDocument.WorkState="Cancelling";UpdateStatus();cancel.IsEnabled=false;try {if(worker!=null && !worker.HasExited){worker.StandardInput.WriteLine("cancel");worker.StandardInput.Flush();}}catch{};}
    static string Quote(string value) {var b=new StringBuilder("\"");int slashes=0;foreach(char c in value){if(c=='\\'){slashes++;continue;}if(c=='\"'){b.Append('\\',slashes*2+1);b.Append(c);}else{b.Append('\\',slashes);b.Append(c);}slashes=0;}b.Append('\\',slashes*2);b.Append('"');return b.ToString();}
    async Task<bool> SaveResult(bool asNew) {
#if CLOSE_REGRESSION
        if(SaveOverride!=null)return await SaveOverride(asNew);
#endif
        if(resultPath==null||busy&&document==jobDocument||loading||canvas.IsLoading)return false;
        if(!asNew && savedPath!=null && File.Exists(savedPath)){status.Text="Already saved: "+savedPath;return true;}
        string destination;bool overwrite=false;
        if(asNew) {
            var dialog=new SaveFileDialog {Title="Save enhanced image",Filter="PNG image|*.png",DefaultExt=".png",AddExtension=true,OverwritePrompt=false,FileName=Path.GetFileNameWithoutExtension(sourcePath)+"_"+resultScale+"x.png",InitialDirectory=Path.GetDirectoryName(sourcePath)};
            if(dialog.ShowDialog(this)!=true)return false;destination=dialog.FileName;
            if(String.Equals(Path.GetFullPath(destination),Path.GetFullPath(sourcePath),StringComparison.OrdinalIgnoreCase)||(File.Exists(destination)&&(File.Exists(sourcePath)&&SameFile(sourcePath,destination)||document!=null&&FileIdentity.Read(destination)==document.Identity))){ShowError("The output must differ from the original input image.");return false;}
            if(File.Exists(destination)){if(Choice("Replace existing image?","Replace "+Path.GetFileName(destination)+"? The original input can never be replaced.",new string[]{"Replace","Cancel"})!=0)return false;overwrite=true;}
        } else destination=FreeOutput(sourcePath,resultScale);
        loading=true;status.Text="Saving PNG…";Refresh();
        try {string final=destination;bool replace=overwrite;string identity=document==null?null:document.Identity;string[] identities=document==null?new string[0]:document.ObservedOriginalIdentities.ToArray();string original=sourcePath,readyResult=resultPath;await Task.Factory.StartNew(()=>{ProtectOriginalIdentities(identities,final);PublishVerified(original,readyResult,final,replace,identity);});savedPath=destination;dirty=false;if(document!=null){document.Result=resultPath;document.Saved=destination;document.ResultScale=resultScale;}StoreDocument();RefreshFolder();status.Text="Saved: "+destination;return true;}
        catch(Exception e){ShowError("Could not save the image. The result is still available.\n\n"+e.Message);status.Text="Save failed · Result remains available";return false;}
        finally {loading=false;Refresh();}
    }
    static string FreeOutput(string original,int factor) {string dir=Path.GetDirectoryName(original),stem=Path.GetFileNameWithoutExtension(original)+"_"+factor+"x";string path=Path.Combine(dir,stem+".png");int n=2;while(File.Exists(path))path=Path.Combine(dir,stem+"_"+(n++)+".png");return path;}
    [StructLayout(LayoutKind.Sequential)] struct FILE_INFO {public uint attributes;public System.Runtime.InteropServices.ComTypes.FILETIME created,accessed,written;public uint volume,sizeHigh,sizeLow,links,indexHigh,indexLow;}
    [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(IntPtr handle,out FILE_INFO info);
    static bool SameFile(string a,string b) {using(var first=new FileStream(a,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete))using(var second=new FileStream(b,FileMode.Open,FileAccess.Read,FileShare.ReadWrite|FileShare.Delete)){FILE_INFO x,y;if(!GetFileInformationByHandle(first.SafeFileHandle.DangerousGetHandle(),out x)||!GetFileInformationByHandle(second.SafeFileHandle.DangerousGetHandle(),out y))throw new IOException("Could not verify file identity.");return x.volume==y.volume&&x.indexHigh==y.indexHigh&&x.indexLow==y.indexLow;}}
    public static void Publish(string original,string result,string destination,bool overwrite){PublishVerified(original,result,destination,overwrite,null);}
    static void PublishVerified(string original,string result,string destination,bool overwrite,string originalIdentity) {
        if(String.Equals(Path.GetFullPath(original),Path.GetFullPath(destination),StringComparison.OrdinalIgnoreCase)||(File.Exists(destination)&&(File.Exists(original)&&SameFile(original,destination)||originalIdentity!=null&&FileIdentity.Read(destination)==originalIdentity)))throw new IOException("The output must differ from the original input image.");
        if(!String.Equals(Path.GetExtension(destination),".png",StringComparison.OrdinalIgnoreCase))throw new IOException("Choose a .png destination.");
        if(File.Exists(destination)&&!overwrite)throw new IOException("The destination already exists. Choose Save As or another filename.");
        string dir=Path.GetDirectoryName(Path.GetFullPath(destination));Directory.CreateDirectory(dir);string temporary=Path.Combine(dir,"."+Path.GetFileNameWithoutExtension(destination)+"-"+Guid.NewGuid().ToString("N")+".png");
        try {File.Copy(result,temporary,false);using(var stream=new FileStream(temporary,FileMode.Open,FileAccess.Write,FileShare.None))stream.Flush(true);if(overwrite&&File.Exists(destination))File.Replace(temporary,destination,null);else File.Move(temporary,destination);}
        finally {if(File.Exists(temporary))File.Delete(temporary);}
    }
    int Choice(string title,string message,string[] labels) {
#if CLOSE_REGRESSION
        if(DecisionOverride!=null)return DecisionOverride(title,message,labels);
#endif
        var dialog=new Window {Title=title,Owner=this,Width=480,SizeToContent=SizeToContent.Height,ResizeMode=ResizeMode.NoResize,WindowStartupLocation=WindowStartupLocation.CenterOwner,ShowInTaskbar=false,Background=Background,FontFamily=FontFamily};int result=labels.Length-1;
        var stack=new StackPanel {Margin=new Thickness(22)};dialog.Content=stack;stack.Children.Add(new TextBlock {Text=message,TextWrapping=TextWrapping.Wrap,FontSize=14,Margin=new Thickness(0,0,0,24)});
        var buttons=new StackPanel {Orientation=Orientation.Horizontal,HorizontalAlignment=HorizontalAlignment.Right};stack.Children.Add(buttons);
        for(int i=0;i<labels.Length;i++){int index=i;var button=new Button();Configure(button,labels[i],delegate {result=index;dialog.DialogResult=true;});button.IsDefault=i==0;buttons.Children.Add(button);}
        dialog.PreviewKeyDown+=delegate(object sender,KeyEventArgs e){if(e.Key==Key.Escape){result=labels.Length-1;dialog.DialogResult=false;e.Handled=true;}};
        dialog.ShowDialog();return result;
    }
    void ShowError(string message) {
#if CLOSE_REGRESSION
        if(ErrorOverride!=null){ErrorOverride(message);return;}
#endif
        MessageBox.Show(this,message,"NCF Image Upscaler",MessageBoxButton.OK,MessageBoxImage.Error);
    }
    void Later(Action action) {Dispatcher.BeginInvoke(action);}
    void OnClosing(object sender,CancelEventArgs e) {
        if(allowClose)return;
        e.Cancel=true;
        if(closingFlow||closeScheduled||commitCloseScheduled||closeWhenDone||quitting)return;
        closeScheduled=true;loadGeneration++;canvas.IsLoading=false;
        // WPF is still inside Closing here. Both prompts and the final Close must
        // run on later Dispatcher turns, after this initial request is cancelled.
        Later(new Action(async delegate {
            closeScheduled=false;
            if(busy||loading||fileWork) {
                closingFlow=true;
                try {
                    closeWhenDone=true;if(busy)CancelWorker();
                    while(busy||loading||fileWork)await Task.Delay(50);
                }finally{closingFlow=false;}
            }
            await FinishClose();
        }));
    }
    async Task FinishClose() {
        if(closingFlow||commitCloseScheduled)return;
        closingFlow=true;
        try {
            bool resolved=true;
            if(browser!=null){StoreDocument();foreach(var pending in browser.Documents.Where(d=>d.Unsaved).ToArray()){await ShowDocument(pending);if(!await ResolveUnsaved()){resolved=false;break;}}}else resolved=await ResolveUnsaved();
            if(resolved) {
                commitCloseScheduled=true;
                Later(new Action(delegate {allowClose=true;Close();}));
            }else closeWhenDone=false;
        }finally{closingFlow=false;}
    }
}
public static class Program {
    [STAThread] public static void Main(string[] args) {var prerequisite=NativePrerequisites.Check();if(prerequisite.Code!=0){MessageBox.Show(NativePrerequisites.Guidance(prerequisite),"NCF Image Upscaler — prerequisite required",MessageBoxButton.OK,MessageBoxImage.Warning);return;}var app=new Application();app.DispatcherUnhandledException+=delegate(object sender,DispatcherUnhandledExceptionEventArgs e){MessageBox.Show(e.Exception.Message,"NCF Image Upscaler",MessageBoxButton.OK,MessageBoxImage.Error);e.Handled=true;};app.Run(new MainWindow(args.Length>0?args[0]:null));}
}
}
