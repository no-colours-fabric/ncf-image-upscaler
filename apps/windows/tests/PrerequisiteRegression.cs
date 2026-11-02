using System;
using NCF;
public static class PrerequisiteRegression {
 static void Check(bool good,string label){if(!good)throw new Exception(label);Console.WriteLine("PASS "+label);}
 public static int Main(){try{
  Check(NativePrerequisites.Evaluate(false,null,false).Code==10,"Missing runtime rejected (controlled)");
  Check(NativePrerequisites.Evaluate(true,new Version(14,28),true).Code==11,"Insufficient version rejected (controlled)");
  Check(NativePrerequisites.Evaluate(true,new Version(14,40),false).Code==12,"Loader/export failure rejected (controlled)");
  Check(NativePrerequisites.Evaluate(true,new Version(14,40),true).Code==0,"Suitable loaded runtime accepted (controlled)");
  var actual=NativePrerequisites.Check();Check(actual.Code==0,"Actual system x64 runtime loads and exports every pinned ORT symbol");
  Console.WriteLine("Actual version: "+actual.Version+"; required named exports: "+RequiredMsvcExports.Names.Length);
  return 0;
 }catch(Exception error){Console.Error.WriteLine(error);return 1;}}
}
