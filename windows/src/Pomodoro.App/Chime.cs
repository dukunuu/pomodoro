using System.Runtime.InteropServices;
using Pomodoro.Core;

namespace Pomodoro.App;

/// <summary>
/// The end-of-phase chime, synthesised rather than shipped as an asset.
///
/// A kitchen timer's bell is a struck tone: a fundamental with a couple of
/// slightly inharmonic partials over an exponential decay. Two are built from
/// that here, so the two announcements are told apart without looking at the
/// screen — a falling pair when focus is over and it is time to stop, a rising
/// triad when a break is over and it is time to start again.
/// </summary>
internal static class Chime
{
    private const int Rate = 44_100;

    private static readonly Lazy<byte[]> FocusOver = new(() => Render(
        new Note(0.00, 880.00, 0.90, 0.85),   // A5
        new Note(0.17, 587.33, 1.35, 1.00))); // D5 — falling, settling

    private static readonly Lazy<byte[]> BreakOver = new(() => Render(
        new Note(0.00, 659.25, 0.45, 0.75),   // E5
        new Note(0.12, 880.00, 0.45, 0.85),   // A5
        new Note(0.24, 1046.50, 0.85, 1.00))); // C6 — rising, brighter

    public static void Play(Phase finished)
    {
        var wave = finished == Phase.Focus ? FocusOver.Value : BreakOver.Value;
        // SND_MEMORY holds no copy, so the buffer has to outlive the playback.
        // SND_SYNC keeps it pinned for the length of the call; the waiting
        // belongs on a background thread rather than on the UI one.
        _ = Task.Run(() =>
        {
            try { PlaySound(wave, IntPtr.Zero, SndMemory | SndSync | SndNoDefault); }
            catch (Exception) { /* no audio device */ }
        });
    }

    private readonly record struct Note(double Start, double Frequency, double Length, double Gain);

    private static byte[] Render(params Note[] notes)
    {
        var frames = (int)(notes.Max(note => note.Start + note.Length) * Rate);
        var samples = new double[frames];

        foreach (var note in notes)
        {
            var start = (int)(note.Start * Rate);
            var length = (int)(note.Length * Rate);
            for (var index = 0; index < length && start + index < frames; index++)
            {
                var t = (double)index / Rate;
                // Decay to near silence by the end of the note, with a 4 ms
                // attack so the strike does not click.
                var envelope = Math.Exp(-3.4 * t / note.Length) * Math.Min(1.0, t / 0.004);
                var w = 2 * Math.PI * note.Frequency * t;
                var tone = Math.Sin(w) + 0.42 * Math.Sin(2.01 * w) + 0.17 * Math.Sin(3.02 * w);
                samples[start + index] += note.Gain * envelope * tone / 1.59;
            }
        }

        var peak = samples.Length == 0 ? 0 : samples.Max(sample => Math.Abs(sample));
        var scale = peak > 0 ? 0.72 * short.MaxValue / peak : 0;

        var wave = new byte[44 + frames * 2];
        var at = 0;
        void Tag(string text)
        {
            foreach (var character in text) wave[at++] = (byte)character;
        }
        void Word(int value)
        {
            wave[at++] = (byte)value;
            wave[at++] = (byte)(value >> 8);
            wave[at++] = (byte)(value >> 16);
            wave[at++] = (byte)(value >> 24);
        }
        void Half(int value)
        {
            wave[at++] = (byte)value;
            wave[at++] = (byte)(value >> 8);
        }

        Tag("RIFF"); Word(36 + frames * 2); Tag("WAVE");
        Tag("fmt "); Word(16); Half(1); Half(1);         // PCM, mono
        Word(Rate); Word(Rate * 2); Half(2); Half(16);   // 16-bit
        Tag("data"); Word(frames * 2);
        foreach (var sample in samples)
        {
            Half((short)Math.Clamp(sample * scale, short.MinValue, short.MaxValue));
        }
        return wave;
    }

    private const uint SndSync = 0x0000;
    private const uint SndNoDefault = 0x0002;
    private const uint SndMemory = 0x0004;

    // DllImport rather than LibraryImport: the source-generated version wants
    // AllowUnsafeBlocks project-wide for a single call.
    [DllImport("winmm.dll", EntryPoint = "PlaySoundW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PlaySound(byte[] sound, IntPtr module, uint flags);
}
