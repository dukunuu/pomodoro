using System.Security.Cryptography;
using System.Text;

namespace Pomodoro.Core;

/// <summary>An optional distributed default is extractable, not a confidential credential.</summary>
public static class OpenRouterCredentials
{
    public const string BundledFilename = "build.dat";
    public enum KeySource { Stored, Environment, Bundled, Missing }

    public static string? Select(string? stored, string? environment, string? bundled) =>
        Clean(stored) ?? Clean(environment) ?? Clean(bundled);

    public static string? Read() => Select(SecretStore.Read(SecretStore.OpenRouterKey),
        System.Environment.GetEnvironmentVariable("OPENROUTER_API_KEY"), BundledKey());

    public static KeySource Source
    {
        get
        {
            if (Clean(SecretStore.Read(SecretStore.OpenRouterKey)) is not null) return KeySource.Stored;
            if (Clean(System.Environment.GetEnvironmentVariable("OPENROUTER_API_KEY")) is not null) return KeySource.Environment;
            return BundledKey() is null ? KeySource.Missing : KeySource.Bundled;
        }
    }

    public static bool Has => Source != KeySource.Missing;

    private static string? BundledKey()
    {
        try { return Unseal(File.ReadAllBytes(Path.Combine(AppContext.BaseDirectory, BundledFilename))); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { return null; }
    }

    private const byte SealVersion = 1;
    private const int SealNonceBytes = 16;
    private static readonly byte[] SealPepper =
    {
        0x9d, 0x3f, 0x6c, 0x1a, 0xe4, 0x72, 0x5b, 0x08, 0xc6, 0xa1, 0xf0, 0x4d, 0x7b, 0xe2, 0x95, 0x38,
        0x17, 0xac, 0x40, 0xe9, 0x6f, 0x2d, 0x8b, 0x5c, 0x03, 0xd1, 0x7e, 0x94, 0xa8, 0x6b, 0xf2, 0x25
    };

    /// <summary>
    /// Reverses tools/bundle-openrouter-key.py. The seal keeps the shared key
    /// from sitting beside the executable as readable text; it is obfuscation,
    /// not encryption, since everything needed to undo it ships in this assembly.
    /// </summary>
    public static string? Unseal(byte[] blob)
    {
        if (blob.Length <= 1 + SealNonceBytes || blob[0] != SealVersion) return null;
        var body = blob.AsSpan(1 + SealNonceBytes);

        var seed = new byte[SealPepper.Length + SealNonceBytes + 4];
        SealPepper.CopyTo(seed, 0);
        blob.AsSpan(1, SealNonceBytes).CopyTo(seed.AsSpan(SealPepper.Length));

        var plain = new byte[body.Length];
        for (int offset = 0, counter = 0; offset < body.Length; counter++)
        {
            System.Buffers.Binary.BinaryPrimitives.WriteUInt32BigEndian(seed.AsSpan(seed.Length - 4), (uint)counter);
            var block = SHA256.HashData(seed);
            for (var i = 0; i < block.Length && offset < body.Length; i++, offset++)
            {
                plain[offset] = (byte)(body[offset] ^ block[i]);
            }
        }
        // Latin-1 maps every byte to one char, so Clean sees exactly what was decoded.
        return Clean(Encoding.Latin1.GetString(plain));
    }

    private static string? Clean(string? value)
    {
        var key = value?.Trim();
        return !string.IsNullOrEmpty(key) && key.All(c => c is >= '!' and <= '~') ? key : null;
    }
}
