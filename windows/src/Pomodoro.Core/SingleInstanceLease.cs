namespace Pomodoro.Core;

/// <summary>Process-held profile ownership. The OS releases it on exit or crash.</summary>
public sealed class SingleInstanceLease : IDisposable
{
    private readonly FileStream _file;
    private SingleInstanceLease(FileStream file) => _file = file;

    public static SingleInstanceLease? Acquire(string directory)
    {
        System.IO.Directory.CreateDirectory(directory);
        try
        {
            return new(new FileStream(Path.Combine(directory, ".pomodoro-app.lock"),
                FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None));
        }
        catch (IOException error) when (OperatingSystem.IsWindows()
            ? (error.HResult & 0xffff) is 32 or 33
            : error.HResult is 11 or 35) { return null; } // sharing violation / EWOULDBLOCK
    }

    // Keep the inode/path in place; deleting it defeats process exclusion.
    public void Dispose() => _file.Dispose();
}
