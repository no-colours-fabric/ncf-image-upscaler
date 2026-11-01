using System;
using System.Collections.Generic;
namespace NCF {
// Percent always describes measured completed inference tiles, never total wall time.
public sealed class ProcessingProgress {
 public string Stage="Preparing";
 public bool FullFrame,Ready;
 public int Completed,Total;
 public void Reset(){Stage="Preparing";FullFrame=false;Ready=false;Completed=Total=0;}
 public void Apply(Dictionary<string,object> data){string kind=Convert.ToString(data["event"]);if(kind=="ready"){Ready=true;Total=Convert.ToInt32(data["total"]);FullFrame=data.ContainsKey("inference_mode")&&Convert.ToString(data["inference_mode"])=="full_frame";Stage="Enhancing";}else if(kind=="progress"){Completed=Convert.ToInt32(data["completed"]);Total=Convert.ToInt32(data["total"]);}else if(kind=="phase"){string phase=Convert.ToString(data["phase"]);Stage=phase=="inference"?"Enhancing":phase=="finishing"?"Finishing image":"Preparing image";}else if(kind=="completed")Stage="Finishing image";}
 public bool Determinate {get{return Ready&&!FullFrame&&Total>0&&Stage=="Enhancing";}}
 public int Percent {get{return Total>0?Math.Max(0,Math.Min(100,(int)Math.Floor(100.0*Completed/Total))):0;}}
 public string Detail {get{return Stage=="Enhancing"?(FullFrame?"Full-frame CPU":Total>0?Percent+"% · "+Completed+" / "+Total+" tiles":"CPU"):Stage=="Finishing image"?"Resizing / saving PNG":"CPU";}}
 public static string Elapsed(TimeSpan elapsed){return elapsed.TotalHours>=1?elapsed.ToString(@"hh\:mm\:ss"):elapsed.ToString(@"mm\:ss");}
}
}
