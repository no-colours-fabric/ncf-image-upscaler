using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
namespace NCF {
public sealed class ThumbnailCache {
 sealed class Entry {public string Revision,Disk;public BitmapSource Image;public Size Pixels;public long Bytes,Used;}
 readonly Dictionary<string,Entry> entries=new Dictionary<string,Entry>();readonly SemaphoreSlim slots=new SemaphoreSlim(2);
 readonly string folder;readonly Func<string,BitmapSource> load;readonly TemporarySession owner;long clock,total;
 public ThumbnailCache(string root,Func<string,BitmapSource> loader,TemporarySession session){owner=session;folder=System.IO.Path.Combine(root,"thumbnails");Directory.CreateDirectory(folder);load=loader;}
 public async Task<BitmapSource> Get(ImageDocument document){string revision=document.Revision,key=document.Path;Entry entry;
  lock(entries){if(entries.TryGetValue(key,out entry)&&entry.Revision==revision&&entry.Image!=null){entry.Used=++clock;document.Pixels=entry.Pixels;return entry.Image;}}
  using(owner.Acquire()){await slots.WaitAsync();try{return await Task.Factory.StartNew(()=>{
   lock(entries){if(entries.TryGetValue(key,out entry)&&entry.Revision==revision&&entry.Image!=null){entry.Used=++clock;document.Pixels=entry.Pixels;return entry.Image;}}
   BitmapSource image;Size pixels;string disk=null;
   if(entry!=null&&entry.Revision==revision&&File.Exists(entry.Disk)){image=MainWindow.LoadBitmap(entry.Disk);pixels=entry.Pixels;disk=entry.Disk;}
   else{var full=load(key);pixels=new Size(full.PixelWidth,full.PixelHeight);double factor=Math.Min(1,512.0/Math.Max(full.PixelWidth,full.PixelHeight));image=factor<1?new TransformedBitmap(full,new ScaleTransform(factor,factor)):full;var converted=new FormatConvertedBitmap(image,PixelFormats.Pbgra32,null,0);byte[] buffer=new byte[converted.PixelWidth*converted.PixelHeight*4];converted.CopyPixels(buffer,converted.PixelWidth*4,0);image=BitmapSource.Create(converted.PixelWidth,converted.PixelHeight,96,96,PixelFormats.Pbgra32,null,buffer,converted.PixelWidth*4);image.Freeze();disk=System.IO.Path.Combine(folder,Guid.NewGuid().ToString("N")+".png");var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(image));using(var s=new FileStream(disk,FileMode.CreateNew))png.Save(s);}
   lock(entries){Entry old;if(entries.TryGetValue(key,out old)){total-=old.Image==null?0:old.Bytes;if(old.Revision!=revision&&File.Exists(old.Disk))File.Delete(old.Disk);}entry=new Entry{Revision=revision,Disk=disk,Image=image,Pixels=pixels,Bytes=image.PixelWidth*(long)image.PixelHeight*4,Used=++clock};entries[key]=entry;total+=entry.Bytes;Trim();}
   if(document.Revision==revision)document.Pixels=pixels;return image;
  });}finally{slots.Release();}}
 }
 void Trim(){foreach(var e in entries.Values.OrderBy(e=>e.Used)){if(total<=48L*1024*1024)break;if(e.Image!=null){e.Image=null;total-=e.Bytes;}}}
 public void Prune(IEnumerable<ImageDocument> docs){lock(entries){var revisions=docs.ToDictionary(d=>d.Path,d=>d.Revision,StringComparer.OrdinalIgnoreCase);foreach(var key in entries.Keys.ToArray()){string r;if(revisions.TryGetValue(key,out r)&&r==entries[key].Revision)continue;var e=entries[key];total-=e.Image==null?0:e.Bytes;try{File.Delete(e.Disk);}catch{}entries.Remove(key);}Trim();}}
}
public sealed class ThumbnailSurface : FrameworkElement {
 public AppearancePalette Palette=AppearancePalette.Create(0);
 public List<ImageDocument> Items=new List<ImageDocument>();public List<Rect> Frames=new List<Rect>();
 public HashSet<ImageDocument> Selected=new HashSet<ImageDocument>();
 public readonly Dictionary<ImageDocument,BitmapSource> Images=new Dictionary<ImageDocument,BitmapSource>();
 public readonly HashSet<ImageDocument> Failed=new HashSet<ImageDocument>();
 public readonly HashSet<ImageDocument> Presented=new HashSet<ImageDocument>(),Loading=new HashSet<ImageDocument>();
 public readonly Dictionary<ImageDocument,Size> SourceSizes=new Dictionary<ImageDocument,Size>();
 public bool Preparing,HasVisibleSkeleton;
 public Action SkeletonChanged;
 public bool ShowsSkeleton(ImageDocument d){return !Images.ContainsKey(d)&&Loading.Contains(d)||Preparing&&!Presented.Contains(d);}
 public bool CanShowImage(ImageDocument d){return Images.ContainsKey(d)&&(!Preparing||Presented.Contains(d));}
 public bool Adaptive;public double Offset,ViewportHeight=500,Pulse=.5;
 public Action<ImageDocument,ModifierKeys,bool> Select;
 public Action<ImageDocument> Request;
 Point down;
 public ThumbnailSurface(){Focusable=true;MouseLeftButtonDown+=delegate(object s,MouseButtonEventArgs e){Focus();down=e.GetPosition(this);var d=Hit(down);if(Select!=null)Select(d,Keyboard.Modifiers,false);e.Handled=true;};MouseRightButtonDown+=delegate(object s,MouseButtonEventArgs e){Focus();var d=Hit(e.GetPosition(this));if(Select!=null)Select(d,Keyboard.Modifiers,true);};MouseMove+=delegate(object s,MouseEventArgs e){if(e.LeftButton==MouseButtonState.Pressed&&(e.GetPosition(this)-down).Length>8&&Selected.Count>0){var data=new DataObject(DataFormats.FileDrop,Selected.Select(d=>d.Path).ToArray());data.SetData("NCF.InternalThumbnailDrag",true);DragDrop.DoDragDrop(this,data,DragDropEffects.Copy|DragDropEffects.Move);}};}
 public ImageDocument Hit(Point p){for(int i=0;i<Frames.Count;i++)if(Frames[i].Contains(p))return Items[i];return null;}
 protected override void OnRender(DrawingContext dc){
  base.OnRender(dc);dc.DrawRectangle(Brushes.Transparent,null,new Rect(0,0,ActualWidth,ActualHeight));bool skeletonVisible=false;
  for(int i=0;i<Items.Count;i++){
   var r=Frames[i];if(r.Bottom<Offset-200||r.Top>Offset+ViewportHeight+200)continue;var d=Items[i];if(Request!=null)Request(d);
   dc.DrawRoundedRectangle(Palette.Card,new Pen(Selected.Contains(d)?Palette.Accent:Palette.Line,Selected.Contains(d)?2:.5),r,10,10);
   var preview=new Rect(r.Left+8,r.Top+8,Math.Max(1,r.Width-16),Math.Max(1,r.Height-58));BitmapSource image;
   if(CanShowImage(d)&&Images.TryGetValue(d,out image)){
    Presented.Add(d);var ir=ImageRect(d.Pixels,preview,!Adaptive);dc.DrawRectangle(ImageCanvas.Checker(Palette.Dark),null,ir);dc.DrawImage(image,ir);
   }else if(ShowsSkeleton(d)){
    Size pixels;var frame=SourceSizes.TryGetValue(d,out pixels)?ImageRect(pixels,preview,!Adaptive):preview;
    dc.DrawRoundedRectangle(Palette.Skeleton,null,frame,6,6);
    dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb((byte)(255*.25*Pulse),255,255,255)),null,frame,6,6);
    if(r.Bottom>=Offset&&r.Top<=Offset+ViewportHeight)skeletonVisible=true;
   }else{
    SvgIcons.Draw(dc,"image",new Rect(preview.Left+(preview.Width-24)/2,preview.Top+(preview.Height-24)/2,24,24),Palette.Muted);
   }
   Text(dc,System.IO.Path.GetFileName(d.Path),11,Palette.Text,new Point(r.Left+8,r.Bottom-43),r.Width-16);
   string detail=d.Processing?d.WorkState:d.Unsaved?"Unsaved":d.Pixels.Width>0?(int)d.Pixels.Width+" × "+(int)d.Pixels.Height:"";Text(dc,detail,10,Palette.Muted,new Point(r.Left+8,r.Bottom-25),r.Width-16);if(d.Unsaved)SvgIcons.Draw(dc,"sparkles",new Rect(r.Right-22,r.Top+5,14,14),Brushes.DarkOrange);
  }
  if(HasVisibleSkeleton!=skeletonVisible){HasVisibleSkeleton=skeletonVisible;if(SkeletonChanged!=null)SkeletonChanged();}
 }
 static Rect ImageRect(Size pixels,Rect bounds,bool enlarge){if(pixels.Width<=0||pixels.Height<=0)return bounds;double factor=Math.Min(enlarge?Double.MaxValue:1,Math.Min(bounds.Width/pixels.Width,bounds.Height/pixels.Height));return new Rect(bounds.Left+(bounds.Width-pixels.Width*factor)/2,bounds.Top+(bounds.Height-pixels.Height*factor)/2,pixels.Width*factor,pixels.Height*factor);}
 static void Text(DrawingContext dc,string text,double size,Brush brush,Point p,double width){if(width<=0)return;var f=new FormattedText(text,System.Globalization.CultureInfo.InvariantCulture,FlowDirection.LeftToRight,new Typeface("Segoe UI"),size,brush,1.0){MaxTextWidth=Math.Max(1,width),MaxLineCount=1,Trimming=TextTrimming.CharacterEllipsis};dc.DrawText(f,p);}
}
public sealed partial class FolderSidebar : Border {
 public Action<ImageDocument> OpenDocument;public Action SelectionChanged;public Action<double> ObstructionChanged;
 public Action<int> FolderRefreshed;
 public Action<string[]> Import;public Action<KeyEventArgs> Navigation;
 public BrowserSession Session;public readonly ThumbnailSurface Surface=new ThumbnailSurface();public readonly ScrollViewer Scroll=new ScrollViewer();
 public readonly TextBox Filter=new TextBox();readonly TextBlock title=new TextBlock();readonly SvgIcon chevron=new SvgIcon("chevron-up",16){HorizontalAlignment=HorizontalAlignment.Right};readonly Grid body=new Grid(),layout=new Grid();readonly Slider slider=new Slider{Minimum=64,Maximum=400,Value=112,MinWidth=60};readonly ComboBox sort=new ComboBox();readonly Thumb resize=new Thumb();readonly Button header=new Button(),regular=new Button(),adaptive=new Button();
 readonly DispatcherTimer refreshTimer=new DispatcherTimer(),pulse=new DispatcherTimer(),clean=new DispatcherTimer();readonly HashSet<ImageDocument> loading=new HashSet<ImageDocument>();
 ThumbnailCache cache;bool updating,collapsed,disposed,manualScrollSinceReveal;double preferred=260;ImageDocument anchor;
 Border backdrop,tint;VisualBrush backdropBrush;
 public void ApplyAppearance(AppearancePalette p){Surface.Palette=p;BorderBrush=p.Line;var rt=new ControlTemplate(typeof(Thumb));var rb=new FrameworkElementFactory(typeof(Border));rb.SetValue(Border.BackgroundProperty,Brushes.Transparent);rt.VisualTree=rb;resize.Template=rt;if(tint!=null)tint.Background=p.Panel;regular.Background=Surface.Adaptive?Brushes.Transparent:p.Active;adaptive.Background=Surface.Adaptive?p.Active:Brushes.Transparent;Surface.InvalidateVisual();}
 public double ThumbnailSize {get{return slider.Value;}}
 public bool Collapsed {get{return collapsed;}}
 public HashSet<ImageDocument> Selected {get{return Surface.Selected;}}
 public void SetBackdrop(Visual viewer){Background=Brushes.Transparent;backdropBrush=new VisualBrush(viewer){ViewboxUnits=BrushMappingMode.Absolute,Stretch=Stretch.Fill};backdrop=new Border{Background=backdropBrush,Effect=new System.Windows.Media.Effects.BlurEffect{Radius=14},IsHitTestVisible=false};Grid.SetRowSpan(backdrop,2);layout.Children.Insert(0,backdrop);tint=new Border{Background=new SolidColorBrush(Color.FromArgb(215,231,231,231)),IsHitTestVisible=false};Grid.SetRowSpan(tint,2);layout.Children.Insert(1,tint);SizeChanged+=delegate{if(ActualWidth>0&&ActualHeight>0){layout.Clip=new RectangleGeometry(new Rect(0,0,ActualWidth,ActualHeight),16,16);backdropBrush.Viewbox=new Rect(Margin.Left,Margin.Top,ActualWidth,ActualHeight);}};}
 public FolderSidebar(){
  HorizontalAlignment=HorizontalAlignment.Left;VerticalAlignment=VerticalAlignment.Stretch;Margin=new Thickness(12);Width=260;CornerRadius=new CornerRadius(16);BorderBrush=new SolidColorBrush(Color.FromArgb(45,0,0,0));BorderThickness=new Thickness(.5);Background=new SolidColorBrush(Color.FromArgb(224,229,229,229));Effect=new System.Windows.Media.Effects.DropShadowEffect{BlurRadius=14,Opacity=.35,ShadowDepth=3};Child=layout;
  layout.RowDefinitions.Add(new RowDefinition{Height=new GridLength(40)});layout.RowDefinitions.Add(new RowDefinition());header.Background=Brushes.Transparent;header.BorderThickness=new Thickness(0);header.Padding=new Thickness(14,6,14,6);header.HorizontalContentAlignment=HorizontalAlignment.Stretch;var heading=new DockPanel();DockPanel.SetDock(chevron,Dock.Right);heading.Children.Add(chevron);heading.Children.Add(new SvgIcon("folder",16){Margin=new Thickness(0,0,6,0)});title.TextTrimming=TextTrimming.CharacterEllipsis;title.FontWeight=FontWeights.SemiBold;title.FontSize=11;heading.Children.Add(title);header.Content=heading;header.Click+=delegate{collapsed=!collapsed;UpdateSize();};layout.Children.Add(header);
  Grid.SetRow(body,1);layout.Children.Add(body);body.Margin=new Thickness(12,0,12,12);body.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});body.RowDefinitions.Add(new RowDefinition{Height=GridLength.Auto});body.RowDefinitions.Add(new RowDefinition());body.RowDefinitions.Add(new RowDefinition{Height=new GridLength(35)});
  var search=new DockPanel();var target=Button("","Locate current image",delegate{Locate();});SvgIcons.Button(target,"crosshair","",16);target.ToolTip="Locate current image";System.Windows.Automation.AutomationProperties.SetName(target,"Locate current image");target.Style=SvgIcons.IconButtonStyle(6);target.Width=26;target.Height=22;DockPanel.SetDock(target,Dock.Right);search.Children.Add(target);Filter.Height=22;Filter.Padding=new Thickness(24,0,2,0);Filter.ToolTip="Filter by name";Filter.Margin=new Thickness(0,0,6,0);Filter.TextChanged+=delegate{if(Session!=null){Session.Filter=Filter.Text;Relayout(false);}};var filterLayer=new Grid();filterLayer.Children.Add(Filter);filterLayer.Children.Add(new SvgIcon("search",14){HorizontalAlignment=HorizontalAlignment.Left,Margin=new Thickness(6,0,0,0)});var hint=new TextBlock{Text="Filter by name",Foreground=Brushes.Gray,Margin=new Thickness(26,2,6,2),IsHitTestVisible=false};filterLayer.Children.Add(hint);Filter.TextChanged+=delegate{hint.Visibility=Filter.Text.Length==0?Visibility.Visible:Visibility.Collapsed;};search.Children.Add(filterLayer);body.Children.Add(search);
  sort.ItemsSource=new[]{"↑ Name","↓ Name","↑ Date Modified","↓ Date Modified","↑ Date Created","↓ Date Created","↑ File Size","↓ File Size","↑ File Type","↓ File Type"};sort.SelectedIndex=0;sort.Margin=new Thickness(0,6,0,6);Grid.SetRow(sort,1);body.Children.Add(sort);sort.SelectionChanged+=delegate{if(Session!=null){Session.SortKey=sort.SelectedIndex/2;Session.Descending=sort.SelectedIndex%2==1;Relayout(false);SavePreferences();}};
  Scroll.Content=Surface;Scroll.HorizontalScrollBarVisibility=ScrollBarVisibility.Disabled;Scroll.VerticalScrollBarVisibility=ScrollBarVisibility.Auto;Scroll.CanContentScroll=false;Scroll.Margin=new Thickness(-4,0,-4,0);Grid.SetRow(Scroll,2);body.Children.Add(Scroll);PreviewMouseWheel+=delegate{manualScrollSinceReveal=true;};Scroll.PreviewMouseDown+=delegate(object sender,MouseButtonEventArgs e){for(DependencyObject node=e.OriginalSource as DependencyObject;node!=null;node=node is Visual?VisualTreeHelper.GetParent(node):LogicalTreeHelper.GetParent(node)){if(node is ScrollBar){manualScrollSinceReveal=true;break;}}};Surface.RequestBringIntoView+=delegate(object sender,RequestBringIntoViewEventArgs e){if(e.TargetObject==Surface)e.Handled=true;};Scroll.ScrollChanged+=delegate{Surface.Offset=Scroll.VerticalOffset;Surface.ViewportHeight=Scroll.ViewportHeight;Surface.InvalidateVisual();};
  var bottom=new DockPanel{Margin=new Thickness(2,10,2,0)};Grid.SetRow(bottom,3);body.Children.Add(bottom);SvgIcons.Button(regular,"grid-2x2","",17);regular.ToolTip="Regular grid";System.Windows.Automation.AutomationProperties.SetName(regular,"Regular grid");SvgIcons.Button(adaptive,"panels-top-left","",17);adaptive.ToolTip="Adaptive grid";System.Windows.Automation.AutomationProperties.SetName(adaptive,"Adaptive grid");regular.Style=adaptive.Style=SvgIcons.IconButtonStyle(13);foreach(var b in new[]{regular,adaptive}){b.Width=26;b.Height=26;b.Padding=new Thickness(0);b.Margin=new Thickness(0,0,8,0);bottom.Children.Add(b);}regular.Click+=delegate{Surface.Adaptive=false;Relayout(true);SavePreferences();};adaptive.Click+=delegate{Surface.Adaptive=true;Relayout(true);SavePreferences();};var icon=new SvgIcon("image",18){Margin=new Thickness(8,0,0,0)};DockPanel.SetDock(icon,Dock.Right);bottom.Children.Add(icon);bottom.Children.Add(slider);slider.ValueChanged+=delegate{if(!updating){UpdateSize();Relayout(true);SavePreferences();}};
  resize.Width=6;resize.Cursor=Cursors.SizeWE;resize.HorizontalAlignment=HorizontalAlignment.Right;resize.Background=Brushes.Transparent;Grid.SetRowSpan(resize,2);layout.Children.Add(resize);resize.DragDelta+=delegate(object s,DragDeltaEventArgs e){preferred=Math.Max(240,Width+e.HorizontalChange);UpdateSize();Relayout(true);SavePreferences();};
  Surface.Select=Select;Surface.Request=QueueRequest;Surface.SkeletonChanged=UpdateSkeletonAnimation;Surface.IsVisibleChanged+=delegate{UpdateSkeletonAnimation();};Surface.PreviewKeyDown+=delegate(object s,KeyEventArgs e){if(Navigation!=null)Navigation(e);};SizeChanged+=delegate{Relayout(true);};
  refreshTimer.Interval=TimeSpan.FromMilliseconds(250);refreshTimer.Tick+=delegate{refreshTimer.Stop();if(Session!=null){int previousIndex=Surface.Items.IndexOf(Session.Current);var before=Session.Documents.ToDictionary(d=>d,d=>d.Revision);Session.Refresh();foreach(var d in Session.Documents){string revision;if(!before.TryGetValue(d,out revision)||revision!=d.Revision)InvalidateRevision(d);}cache.Prune(Session.Documents);Relayout(true);if(FolderRefreshed!=null)FolderRefreshed(previousIndex);}};
  double phase=0;pulse.Interval=TimeSpan.FromMilliseconds(60);pulse.Tick+=delegate{phase+=.06;Surface.Pulse=.15+.7*(1-Math.Cos(phase*Math.PI/.9))/2;Surface.InvalidateVisual();};
  clean.Interval=TimeSpan.FromSeconds(60);clean.Tick+=delegate{if(Session!=null)cache.Prune(Session.Documents);};clean.Start();ReadPreferences();Visibility=Visibility.Collapsed;
  AllowDrop=true;DragOver+=delegate(object s,DragEventArgs e){e.Effects=e.Data.GetDataPresent(DataFormats.FileDrop)&&!e.Data.GetDataPresent("NCF.InternalThumbnailDrag")?DragDropEffects.Copy:DragDropEffects.None;e.Handled=true;};Drop+=delegate(object s,DragEventArgs e){var paths=e.Data.GetData(DataFormats.FileDrop) as string[];if(paths!=null&&Import!=null&&!e.Data.GetDataPresent("NCF.InternalThumbnailDrag"))Import(paths);e.Handled=true;};
 }
 static Button Button(string label,string tip,RoutedEventHandler click){var b=new Button{Content=label,ToolTip=tip,Background=Brushes.Transparent,BorderThickness=new Thickness(0)};b.Click+=click;return b;}
 public void Attach(BrowserSession session,string root,Func<string,BitmapSource> loader,TemporarySession owner){Session=session;lifetime=owner;cache=new ThumbnailCache(root,loader,owner);Surface.Images.Clear();Surface.Failed.Clear();Surface.Presented.Clear();Surface.Loading.Clear();Surface.SourceSizes.Clear();metadataAttempts.Clear();imageVersions.Clear();Surface.Selected.Clear();loading.Clear();Filter.Text=session.Filter;session.SortKey=sort.SelectedIndex/2;session.Descending=sort.SelectedIndex%2==1;session.Changed=()=>Dispatcher.BeginInvoke(new Action(delegate{if(disposed)return;refreshTimer.Stop();refreshTimer.Start();}));Visibility=Visibility.Visible;UpdateSize();Relayout(false);}
 public void UpdateSize(){double parent=Parent is FrameworkElement?((FrameworkElement)Parent).ActualWidth:1280;if(parent<=0)parent=1280;Width=collapsed?Math.Max(180,Math.Min(300,title.Text.Length*7+64)):Math.Min(parent/2,Math.Max(Math.Max(240,slider.Value+60),preferred));Height=collapsed?44:Double.NaN;VerticalAlignment=collapsed?VerticalAlignment.Top:VerticalAlignment.Stretch;body.Visibility=resize.Visibility=collapsed?Visibility.Collapsed:Visibility.Visible;title.Text=Session==null?"":System.IO.Path.GetFileName(Session.Folder);chevron.IconName=collapsed?"chevron-down":"chevron-up";header.ToolTip=collapsed?"Expand folder panel":"Collapse folder panel";System.Windows.Automation.AutomationProperties.SetName(header,header.ToolTip.ToString());if(ObstructionChanged!=null)ObstructionChanged(collapsed?0:Width+24);}
 public void Relayout(bool keep){if(Session==null||updating||disposed)return;updating=true;try{EnsureMetadata();Surface.Preparing=Surface.Adaptive&&metadataBatches>0;var oldItems=Surface.Items.ToArray();var oldFrames=Surface.Frames.ToArray();var current=Session.Current;bool was=current!=null&&Visible(current);ImageDocument scrollAnchor=null;double anchorOffset=0;for(int i=0;i<Surface.Items.Count;i++){if(Surface.Frames[i].Bottom>=Scroll.VerticalOffset&&Surface.Frames[i].Top<=Scroll.VerticalOffset+Scroll.ViewportHeight){scrollAnchor=Surface.Items[i];anchorOffset=Scroll.VerticalOffset-Surface.Frames[i].Top;break;}}Surface.Items=Session.Visible();var sizes=Surface.Items.Select((d,i)=>LayoutSize(d,i)).ToArray();double w=Math.Max(1,(Scroll.ViewportWidth>0?Scroll.ViewportWidth:Width-24));Surface.Frames=BrowserLayout.Calculate(w,slider.Value,Surface.Adaptive,sizes);bool geometryChanged=!oldItems.SequenceEqual(Surface.Items)||!oldFrames.SequenceEqual(Surface.Frames);Surface.Width=w;Surface.Height=Surface.Frames.Count==0?16:Surface.Frames.Max(r=>r.Bottom)+8;Surface.InvalidateVisual();regular.Background=Surface.Adaptive?Brushes.Transparent:Surface.Palette.Active;adaptive.Background=Surface.Adaptive?Surface.Palette.Active:Brushes.Transparent;if(geometryChanged&&keep&&scrollAnchor!=null){int index=Surface.Items.IndexOf(scrollAnchor);if(index>=0)Scroll.ScrollToVerticalOffset(Surface.Frames[index].Top+anchorOffset);}if(geometryChanged&&keep&&was&&!manualScrollSinceReveal)Reveal(current);UpdateSkeletonAnimation();}finally{updating=false;}}
 bool Visible(ImageDocument d){int i=Surface.Items.IndexOf(d);return i>=0&&Surface.Frames[i].Bottom>=Scroll.VerticalOffset&&Surface.Frames[i].Top<=Scroll.VerticalOffset+Scroll.ViewportHeight;}
 public void Reveal(ImageDocument d){int i=Surface.Items.IndexOf(d);if(i<0)return;Scroll.ScrollToVerticalOffset(BrowserNavigation.RevealOffset(Surface.Frames[i],Scroll.VerticalOffset,Scroll.ViewportHeight));}
 public void Locate(){if(Session==null||Session.Current==null)return;manualScrollSinceReveal=false;collapsed=false;if(!Session.Visible().Contains(Session.Current)){Filter.Text="";Session.Filter="";}UpdateSize();Relayout(false);Selected.Clear();Selected.Add(Session.Current);anchor=Session.Current;Surface.Focus();Reveal(Session.Current);Surface.InvalidateVisual();}
 public void LocateForNavigation(ImageDocument d){manualScrollSinceReveal=false;collapsed=false;UpdateSize();Relayout(false);Surface.Focus();Reveal(d);}
 public void Select(ImageDocument d,ModifierKeys modifiers,bool context){if(context&&d!=null&&Selected.Contains(d))return;if(d==null)Selected.Clear();else if((modifiers&ModifierKeys.Shift)!=0&&anchor!=null){int a=Surface.Items.IndexOf(anchor),b=Surface.Items.IndexOf(d);Selected.Clear();if(a<0)a=b;for(int i=Math.Min(a,b);i<=Math.Max(a,b);i++)Selected.Add(Surface.Items[i]);}else if((modifiers&ModifierKeys.Control)!=0){if(!Selected.Add(d))Selected.Remove(d);anchor=d;}else{Selected.Clear();Selected.Add(d);anchor=d;}if(d!=null){Session.Current=d;if(OpenDocument!=null)OpenDocument(d);}Surface.InvalidateVisual();if(SelectionChanged!=null)SelectionChanged();}
 async void Request(ImageDocument d){
  if(disposed||cache==null){loading.Remove(d);Surface.Loading.Remove(d);return;}var owner=Session;string revision=d.Revision;
  try{var bitmap=await cache.Get(d);if(!disposed&&Session==owner&&d.Revision==revision){Surface.Images[d]=bitmap;imageVersions[d]=revision;Relayout(true);foreach(var other in Surface.Images.Keys.ToArray()){int index=Surface.Items.IndexOf(other);if(index<0||Surface.Frames[index].Bottom<Scroll.VerticalOffset-300||Surface.Frames[index].Top>Scroll.VerticalOffset+Scroll.ViewportHeight+300)Surface.Images.Remove(other);}}}
  catch{if(!disposed&&Session==owner&&d.Revision==revision)Surface.Failed.Add(d);}
  finally{loading.Remove(d);Surface.Loading.Remove(d);Surface.InvalidateVisual();}
 }
 string Preferences {get{return System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"NCF Image Upscaler","sidebar.preferences");}}
 void ReadPreferences(){try{var a=File.ReadAllLines(Preferences);updating=true;preferred=Double.Parse(a[0],System.Globalization.CultureInfo.InvariantCulture);slider.Value=Double.Parse(a[1],System.Globalization.CultureInfo.InvariantCulture);sort.SelectedIndex=Int32.Parse(a[2]);Surface.Adaptive=a[3]=="adaptive";}catch{}finally{updating=false;}}
 void SavePreferences(){try{File.WriteAllLines(Preferences,new[]{preferred.ToString(System.Globalization.CultureInfo.InvariantCulture),slider.Value.ToString(System.Globalization.CultureInfo.InvariantCulture),sort.SelectedIndex.ToString(),Surface.Adaptive?"adaptive":"regular"});}catch{}}
 public void Dispose(){disposed=true;metadataStop.Cancel();pulse.Stop();clean.Stop();refreshTimer.Stop();if(Session!=null)Session.Changed=null;}
}
}
