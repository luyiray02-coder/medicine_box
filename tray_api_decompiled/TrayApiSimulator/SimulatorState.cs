using System;
using System.Collections.Generic;
using System.Linq;

namespace TrayApiSimulator;

internal sealed class SimulatorState
{
	private readonly object _gate = new object();

	private readonly decimal[] _weights = new decimal[4];

	private readonly bool[] _lights = new bool[4];

	private decimal _temperature = 28m;

	private decimal _humidity = 60m;

	public event EventHandler<LightChangedEventArgs>? LightChanged;

	public decimal[] GetWeights()
	{
		lock (_gate)
		{
			return (decimal[])_weights.Clone();
		}
	}

	public (decimal Temperature, decimal Humidity) GetEnvironment()
	{
		lock (_gate)
		{
			return (Temperature: _temperature, Humidity: _humidity);
		}
	}

	public bool[] GetLights()
	{
		lock (_gate)
		{
			return (bool[])_lights.Clone();
		}
	}

	public void SetMeasurements(IReadOnlyList<decimal> weights, decimal temperature, decimal humidity)
	{
		ArgumentNullException.ThrowIfNull(weights, "weights");
		if (weights.Count != 4 || weights.Any((decimal weight) => weight < 0m))
		{
			throw new ArgumentOutOfRangeException("weights", "Exactly four non-negative weights are required.");
		}
		if ((humidity < 0m || humidity > 100m) ? true : false)
		{
			throw new ArgumentOutOfRangeException("humidity", "Humidity must be between 0 and 100.");
		}
		lock (_gate)
		{
			for (int num = 0; num < 4; num++)
			{
				_weights[num] = weights[num];
			}
			_temperature = temperature;
			_humidity = humidity;
		}
	}

	public void SetLight(int target, bool isOn)
	{
		ValidateTarget(target);
		lock (_gate)
		{
			_lights[target - 1] = isOn;
		}
		LightChanged?.Invoke(this, new LightChangedEventArgs(target, isOn));
	}

	public void ToggleLight(int target)
	{
		ValidateTarget(target);
		bool flag;
		lock (_gate)
		{
			flag = !_lights[target - 1];
			_lights[target - 1] = flag;
		}
		LightChanged?.Invoke(this, new LightChangedEventArgs(target, flag));
	}

	private static void ValidateTarget(int target)
	{
		if ((target < 1 || target > 4) ? true : false)
		{
			throw new ArgumentOutOfRangeException("target", "Target must be from 1 to 4.");
		}
	}
}
