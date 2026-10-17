using System;
using System.Windows.Forms;

namespace TrayApiSimulator;

internal static class Program
{
	[STAThread]
	private static void Main()
	{
		ApplicationConfiguration.Initialize();
		SimulatorState state = new SimulatorState();
		ApiHost apiHost = null;
		string apiStartupError = null;
		try
		{
			apiHost = new ApiHost(state);
			apiHost.StartAsync().GetAwaiter().GetResult();
		}
		catch (Exception ex)
		{
			apiStartupError = ex.GetBaseException().Message;
		}
		try
		{
			Application.Run(new MainForm(state, apiStartupError));
		}
		finally
		{
			apiHost?.DisposeAsync().AsTask().GetAwaiter()
				.GetResult();
		}
	}
}
