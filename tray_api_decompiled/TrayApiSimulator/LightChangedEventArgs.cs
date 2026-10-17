using System;

namespace TrayApiSimulator;

internal sealed class LightChangedEventArgs(int target, bool isOn) : EventArgs
{
	public int Target { get; } = target;

	public bool IsOn { get; } = isOn;
}
