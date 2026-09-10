using System.Runtime.InteropServices;
using System.Text;

namespace Pomodoro.Core;

/// <summary>
/// Secrets in the Windows Credential Manager rather than in a file.
///
/// The session token and the OpenRouter key used to live in
/// pomodoro-whistler.env as plain text, beside the account password the user
/// had typed there to obtain the token. Credential Manager encrypts per user,
/// is where Windows expects an application's credentials to be, and lets the
/// user inspect and revoke them without going through this app.
/// </summary>
public static class SecretStore
{
    public const string WhistlerSession = "whistler-session";
    public const string OpenRouterKey = "openrouter-key";

    private const string Prefix = "Pomodoro:";

    public static bool Has(string key) => !string.IsNullOrEmpty(Read(key));

    public static string? Read(string key)
    {
        if (!CredRead(Prefix + key, GenericCredential, 0, out var handle)) return null;
        try
        {
            var credential = Marshal.PtrToStructure<Credential>(handle);
            if (credential.CredentialBlobSize == 0 || credential.CredentialBlob == IntPtr.Zero)
            {
                return null;
            }
            var bytes = new byte[credential.CredentialBlobSize];
            Marshal.Copy(credential.CredentialBlob, bytes, 0, bytes.Length);
            // UTF-8 rather than UTF-16: the blob is capped at 2560 bytes and a
            // session token is long enough that the difference matters.
            return Encoding.UTF8.GetString(bytes);
        }
        catch (Exception)
        {
            return null;
        }
        finally
        {
            CredFree(handle);
        }
    }

    /// <summary>Storing an empty value removes the credential.</summary>
    public static void Write(string key, string value)
    {
        if (string.IsNullOrEmpty(value)) { Delete(key); return; }

        var bytes = Encoding.UTF8.GetBytes(value);
        if (bytes.Length > 2560)
        {
            throw new InvalidOperationException("That credential is too long to store.");
        }

        var blob = Marshal.AllocHGlobal(bytes.Length);
        var target = Marshal.StringToHGlobalUni(Prefix + key);
        var user = Marshal.StringToHGlobalUni("Pomodoro");
        try
        {
            Marshal.Copy(bytes, 0, blob, bytes.Length);
            var credential = new Credential
            {
                Type = GenericCredential,
                TargetName = target,
                CredentialBlobSize = (uint)bytes.Length,
                CredentialBlob = blob,
                Persist = PersistLocalMachine,
                UserName = user
            };
            if (!CredWrite(ref credential, 0))
            {
                throw new InvalidOperationException(
                    $"Windows would not store the credential (error {Marshal.GetLastWin32Error()}).");
            }
        }
        finally
        {
            Marshal.FreeHGlobal(blob);
            Marshal.FreeHGlobal(target);
            Marshal.FreeHGlobal(user);
        }
    }

    public static void Delete(string key)
    {
        try { CredDelete(Prefix + key, GenericCredential, 0); }
        catch (Exception) { /* nothing stored under that name */ }
    }

    private const uint GenericCredential = 1;
    private const uint PersistLocalMachine = 2;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct Credential
    {
        public uint Flags;
        public uint Type;
        public IntPtr TargetName;
        public IntPtr Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public uint CredentialBlobSize;
        public IntPtr CredentialBlob;
        public uint Persist;
        public uint AttributeCount;
        public IntPtr Attributes;
        public IntPtr TargetAlias;
        public IntPtr UserName;
    }

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, EntryPoint = "CredReadW", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredRead(string target, uint type, uint flags, out IntPtr credential);

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, EntryPoint = "CredWriteW", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredWrite(ref Credential credential, uint flags);

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, EntryPoint = "CredDeleteW", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CredDelete(string target, uint type, uint flags);

    [DllImport("advapi32.dll")]
    private static extern void CredFree(IntPtr buffer);
}
