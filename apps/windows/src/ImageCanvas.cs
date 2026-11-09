using System;
using System.Globalization;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
namespace NCF {
public sealed class ViewPosition {
 public double DisplayedWidth,CenterX=.5,CenterY=.5,Divider=.5; public bool Fitting=true;
}
// Windows DIPs correspond to AppKit logical points. No native window dependency.
public sealed class ViewGeometry {
 public double Width=1,Height=1,CanvasWidth=1,CanvasHeight=1,Obstruction,Zoom=1,CenterX=.5,CenterY=.5,Divider=.5;
 public bool Fitting=true;
 public Rect Viewport {get{return new Rect(Math.Min(Width,Math.Max(0,Obstruction)),0,Math.Max(0,Width-Obstruction),Math.Max(0,Height));}}
 public double FitScale {get{return Math.Max(.01,Math.Min((Viewport.Width-48)/CanvasWidth,(Viewport.Height-48)/CanvasHeight));}}
 public Rect ImageRect {get{var v=Viewport;return new Rect(v.Left+v.Width/2-CenterX*CanvasWidth*Zoom,v.Height/2-CenterY*CanvasHeight*Zoom,CanvasWidth*Zoom,CanvasHeight*Zoom);}}
 public Rect Visible {get{var r=Rect.Intersect(ImageRect,Viewport);return r.IsEmpty||r.Width<=0||r.Height<=0?Rect.Empty:r;}}
 public double DividerX {get{var r=Visible;return r.IsEmpty?0:r.Left+Divider*r.Width;}}
 public void Clamp(){double dw=CanvasWidth*Zoom,dh=CanvasHeight*Zoom;var v=Viewport;CenterX=dw<=v.Width?.5:Math.Max(v.Width/(2*dw),Math.Min(1-v.Width/(2*dw),CenterX));CenterY=dh<=v.Height?.5:Math.Max(v.Height/(2*dh),Math.Min(1-v.Height/(2*dh),CenterY));}
 public void Fit(bool cap){Zoom=cap?Math.Min(1,FitScale):FitScale;Fitting=!(cap&&FitScale>1);CenterX=CenterY=.5;Clamp();}
 public void Resize(double width,double height,double obstruction){width=Math.Max(1,width);height=Math.Max(1,height);obstruction=Math.Min(width,Math.Max(0,obstruction));if(Width==width&&Height==height&&Obstruction==obstruction)return;Width=width;Height=height;Obstruction=obstruction;if(Fitting)Fit(false);else Clamp();}
 public void ZoomAt(double value,Point point){var r=ImageRect;double x=(point.X-r.X)/r.Width,y=(point.Y-r.Y)/r.Height;Zoom=Math.Max(.01,Math.Min(Math.Max(32,FitScale),value));Fitting=false;var v=Viewport;CenterX=x+(v.Left+v.Width/2-point.X)/(CanvasWidth*Zoom);CenterY=y+(v.Height/2-point.Y)/(CanvasHeight*Zoom);Clamp();}
 public void Attach(double w,double h){double old=CanvasWidth;CanvasWidth=w;CanvasHeight=h;if(Fitting)Fit(false);else{Zoom=Math.Max(.01,Zoom*old/w);Clamp();}}
 public ViewPosition Save(){return new ViewPosition{DisplayedWidth=CanvasWidth*Zoom,CenterX=CenterX,CenterY=CenterY,Divider=Divider,Fitting=Fitting};}
 public void Restore(ViewPosition p){CenterX=p.CenterX;CenterY=p.CenterY;Divider=Math.Max(0,Math.Min(1,p.Divider));Fitting=p.Fitting;if(Fitting)Fit(false);else{Zoom=Math.Max(.01,p.DisplayedWidth/CanvasWidth);Clamp();}}
}
public sealed class ImageCanvas : FrameworkElement {
 public AppearancePalette Palette=AppearancePalette.Create(0);
 public BitmapSource Original,Result;
 public string ViewMode="Compare";
 public Action ZoomChanged;
 public readonly ViewGeometry Geometry=new ViewGeometry();
 bool dragDivider,dragPan,hasAlpha; Point last; readonly Brush checker=Checker(),darkChecker=Checker(true);
 bool isLoading;double loadingPhase;
 readonly System.Windows.Threading.DispatcherTimer loadingTimer=new System.Windows.Threading.DispatcherTimer();
 public bool IsLoading {get{return isLoading;}set{if(isLoading==value)return;isLoading=value;if(value)loadingPhase=0;UpdateLoadingAnimation();InvalidateVisual();}}
 public bool LoadingAnimationRunning {get{return loadingTimer.IsEnabled;}}
 void UpdateLoadingAnimation(){if(isLoading&&IsVisible&&SystemParameters.ClientAreaAnimation)loadingTimer.Start();else loadingTimer.Stop();}
 public bool HasAlpha {get{return hasAlpha;}}
 public ImageCanvas(){Focusable=true;ClipToBounds=true;loadingTimer.Interval=TimeSpan.FromMilliseconds(40);loadingTimer.Tick+=delegate{loadingPhase=(loadingPhase+.035)%1;InvalidateVisual();};IsVisibleChanged+=delegate{UpdateLoadingAnimation();};Unloaded+=delegate{loadingTimer.Stop();};RenderOptions.SetBitmapScalingMode(this,BitmapScalingMode.HighQuality);MouseWheel+=Wheel;MouseDown+=Down;MouseMove+=Move;MouseUp+=delegate{dragDivider=dragPan=false;ReleaseMouseCapture();Cursor=Cursors.Arrow;};SizeChanged+=delegate{Geometry.Resize(ActualWidth,ActualHeight,Geometry.Obstruction);Changed();};}
 public static Brush Checker(){return Checker(false);}
 public static Brush Checker(bool dark){var d=new DrawingGroup();d.Children.Add(new GeometryDrawing(new SolidColorBrush(dark?Color.FromRgb(54,57,63):Color.FromRgb(245,245,245)),null,new RectangleGeometry(new Rect(0,0,18,18))));var b=new SolidColorBrush(dark?Color.FromRgb(43,46,52):Color.FromRgb(222,222,222));foreach(var r in new[]{new Rect(0,0,9,9),new Rect(9,9,9,9)})d.Children.Add(new GeometryDrawing(b,null,new RectangleGeometry(r)));var brush=new DrawingBrush(d){Viewport=new Rect(0,0,18,18),ViewportUnits=BrushMappingMode.Absolute,TileMode=TileMode.Tile,Stretch=Stretch.None};brush.Freeze();return brush;}
 static bool Alpha(BitmapSource i){return i!=null&&(i.Format==PixelFormats.Bgra32||i.Format==PixelFormats.Pbgra32||i.Format==PixelFormats.Rgba64||i.Format==PixelFormats.Prgba64||i.Format==PixelFormats.Rgba128Float||i.Format==PixelFormats.Prgba128Float||i.Palette!=null&&System.Linq.Enumerable.Any(i.Palette.Colors,c=>c.A<255));}
 public double Percent {get{return Original==null?100:Geometry.Zoom*100;}}
 public double LeadingObstruction {get{return Geometry.Obstruction;}set{Geometry.Resize(ActualWidth,ActualHeight,value);Changed();}}
 public ViewPosition Position {get{return Geometry.Save();}set{if(value!=null)Geometry.Restore(value);Changed();}}
 void Changed(){InvalidateVisual();if(ZoomChanged!=null)ZoomChanged();}
 public void Fit(){if(Original==null)return;Geometry.Fit(false);Changed();}
 public void ActualPixels(){if(Original==null)return;var v=Geometry.Viewport;Geometry.ZoomAt(1,new Point(v.Left+v.Width/2,v.Height/2));Changed();}
 public void ZoomBy(double factor){var v=Geometry.Viewport;Geometry.ZoomAt(Geometry.Zoom*factor,new Point(v.Left+v.Width/2,v.Height/2));Changed();}
 public void SetOriginal(BitmapSource image){SetImages(image,null,null);}
 public void SetImages(BitmapSource original,BitmapSource result,ViewPosition position){Original=original;Result=result;hasAlpha=Alpha(original)||Alpha(result);var c=result??original;Geometry.CanvasWidth=c==null?1:c.PixelWidth;Geometry.CanvasHeight=c==null?1:c.PixelHeight;Geometry.Divider=.5;if(position==null)Geometry.Fit(true);else Geometry.Restore(position);Changed();}
 public void SetResult(BitmapSource image){Result=image;hasAlpha=Alpha(Original)||Alpha(Result);Geometry.Attach(image.PixelWidth,image.PixelHeight);ViewMode="Compare";Changed();}
 protected override void OnRender(DrawingContext dc){base.OnRender(dc);RenderContent(dc);if(IsLoading){var v=Geometry.Viewport;double width=Math.Min(80,Math.Max(0,v.Width-32));var track=new Rect(v.Left+16,Math.Max(0,v.Bottom-20),width,4);dc.DrawRoundedRectangle(Brushes.LightGray,null,track,2,2);double segment=width*.4,offset=SystemParameters.ClientAreaAnimation?(width+segment)*loadingPhase-segment:(width-segment)/2;dc.PushClip(new RectangleGeometry(track,2,2));dc.DrawRoundedRectangle(Brushes.DodgerBlue,null,new Rect(track.Left+offset,track.Top,segment,4),2,2);dc.Pop();}}
 void RenderContent(DrawingContext dc){var bounds=new Rect(0,0,ActualWidth,ActualHeight);dc.DrawRectangle(Original==null?Palette.Viewer:hasAlpha?(Palette.Dark?darkChecker:checker):Brushes.Black,null,bounds);if(Original==null){SvgIcons.Draw(dc,"image",new Rect(Math.Max(24,(ActualWidth-58)/2),Math.Max(0,ActualHeight/2-80),58,58),Brushes.Gray);Text(dc,"Open an Image",24,Brushes.Gray,new Point(Math.Max(24,(ActualWidth-175)/2),Math.Max(0,ActualHeight/2)));Text(dc,"Drag a file here or press Ctrl+O",13,Brushes.Gray,new Point(Math.Max(24,(ActualWidth-215)/2),Math.Max(0,ActualHeight/2+38)));return;}var rect=Geometry.ImageRect;dc.DrawImage(Original,rect);if(Result==null)return;var visible=Geometry.Visible;if(visible.IsEmpty)return;double x=Geometry.DividerX;dc.PushClip(new RectangleGeometry(new Rect(x,0,Math.Max(0,ActualWidth-x),ActualHeight)));dc.DrawImage(Result,rect);dc.Pop();dc.PushClip(new RectangleGeometry(Geometry.Viewport));dc.DrawLine(new Pen(new SolidColorBrush(Color.FromArgb(100,0,0,0)),4),new Point(x,visible.Top),new Point(x,visible.Bottom));dc.DrawLine(new Pen(Brushes.WhiteSmoke,1),new Point(x,visible.Top),new Point(x,visible.Bottom));var middle=new Point(x,visible.Top+visible.Height/2);dc.DrawEllipse(Brushes.White,null,middle,10,10);for(int i=-1;i<=1;i+=2)dc.DrawLine(new Pen(Brushes.Gray,1),new Point(x+i*2,middle.Y-4),new Point(x+i*2,middle.Y+4));Badge(dc,"Original",new Point(visible.Left+12,visible.Top+12));Badge(dc,"Result",new Point(Math.Max(visible.Left+12,visible.Right-63),visible.Top+12));dc.Pop();}
 static void Badge(DrawingContext dc,string value,Point p){dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(128,0,0,0)),null,new Rect(p.X,p.Y,value=="Original"?67:51,24),7,7);Text(dc,value,11,Brushes.White,new Point(p.X+9,p.Y+5));}
 static void Text(DrawingContext dc,string text,double size,Brush brush,Point point){dc.DrawText(new FormattedText(text,CultureInfo.InvariantCulture,FlowDirection.LeftToRight,new Typeface("Segoe UI"),size,brush,1.0),point);}
 bool DividerHit(Point p){return Result!=null&&!Geometry.Visible.IsEmpty&&Geometry.Visible.Contains(p)&&Math.Abs(p.X-Geometry.DividerX)<=13;}
 void Down(object sender,MouseButtonEventArgs e){Focus();last=e.GetPosition(this);if(e.ChangedButton!=MouseButton.Left)return;if(e.ClickCount%2==0){if(Geometry.Fitting)ActualPixels();else Fit();e.Handled=true;return;}if(Original==null)return;dragDivider=DividerHit(last);dragPan=!dragDivider;Cursor=dragDivider?Cursors.SizeWE:Cursors.Hand;CaptureMouse();e.Handled=true;}
 void Move(object sender,MouseEventArgs e){var p=e.GetPosition(this);if(dragDivider){var r=Geometry.Visible;if(!r.IsEmpty)Geometry.Divider=Math.Max(0,Math.Min(1,(p.X-r.Left)/r.Width));InvalidateVisual();}else if(dragPan){Geometry.CenterX-=(p.X-last.X)/(Geometry.CanvasWidth*Geometry.Zoom);Geometry.CenterY-=(p.Y-last.Y)/(Geometry.CanvasHeight*Geometry.Zoom);Geometry.Clamp();InvalidateVisual();}else Cursor=DividerHit(p)?Cursors.SizeWE:Cursors.Arrow;last=p;}
 void Wheel(object sender,MouseWheelEventArgs e){if(Original==null)return;Geometry.ZoomAt(Geometry.Zoom*Math.Exp(e.Delta/120.0*.055),e.GetPosition(this));Changed();e.Handled=true;}
}
}
