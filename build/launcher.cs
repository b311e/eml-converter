using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;

static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        string tmp = Path.Combine(Path.GetTempPath(), "eml2pdf_" + Guid.NewGuid().ToString("N") + ".ps1");
        using (Stream s = Assembly.GetExecutingAssembly().GetManifestResourceStream("script.ps1"))
        using (FileStream f = File.Create(tmp))
            s.CopyTo(f);
        var sb = new StringBuilder();
        foreach (string a in args) sb.Append('"').Append(a).Append("\" ");
        var psi = new ProcessStartInfo("powershell.exe",
            "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"" + tmp + "\"");
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        psi.EnvironmentVariables["EML_ARGS"] = sb.ToString().Trim();
        try { using (Process p = Process.Start(psi)) { p.WaitForExit(); return p.ExitCode; } }
        finally { try { File.Delete(tmp); } catch { } }
    }
}
