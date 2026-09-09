namespace Pomodoro.Core;

/// <summary>
/// Whole-file reads and atomic replaces, mirroring the guarantees the
/// Quickshell <c>FileView</c> gave the QML service. An external editor may
/// also write these files, so every write replaces the file wholesale.
/// </summary>
public static class AtomicFile
{
    public static string? Read(string path)
    {
        try
        {
            return File.Exists(path) ? File.ReadAllText(path) : null;
        }
        catch (IOException)
        {
            return null;
        }
        catch (UnauthorizedAccessException)
        {
            return null;
        }
    }

    public static bool Write(string path, string text)
    {
        try
        {
            DataPaths.EnsureDirectory();
            var temp = path + ".tmp";
            File.WriteAllText(temp, text);
            // File.Move with overwrite is atomic enough on NTFS for our purpose:
            // a reader either sees the old file or the new one, never a partial.
            File.Move(temp, path, overwrite: true);
            return true;
        }
        catch (IOException)
        {
            return false;
        }
        catch (UnauthorizedAccessException)
        {
            return false;
        }
    }
}
