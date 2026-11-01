using System;
namespace NCF {
public static class PrerequisiteProbe {
 public static int Main(){try{var result=NativePrerequisites.Check();Console.WriteLine(result.Message);return result.Code;}catch{Console.Error.WriteLine("Could not verify the Microsoft Visual C++ x64 Runtime.");return 12;}}
}
}
