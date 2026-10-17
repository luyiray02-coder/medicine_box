using System;
using System.Globalization;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Server.Kestrel.Core;

namespace TrayApiSimulator;

internal sealed class ApiHost : IAsyncDisposable
{
	private readonly WebApplication _application;

	private bool _started;

	public ApiHost(SimulatorState state)
	{
		WebApplicationBuilder webApplicationBuilder = WebApplication.CreateBuilder(new WebApplicationOptions
		{
			Args = Array.Empty<string>(),
			ContentRootPath = AppContext.BaseDirectory
		});
		webApplicationBuilder.WebHost.ConfigureKestrel(delegate(KestrelServerOptions options)
		{
			options.ListenLocalhost(8080, delegate(ListenOptions listenOptions)
			{
				listenOptions.UseHttps();
			});
		});
		_application = webApplicationBuilder.Build();
		_application.MapGet("/api/weight", (Func<IResult>)(() => Results.Json(state.GetWeights())));
		_application.MapGet("/api/status", (Func<IResult>)delegate
		{
			var (tem, hum) = state.GetEnvironment();
			return Results.Json(new { tem, hum });
		});
		_application.MapGet("/api/lightStatus", (Func<IResult>)(() => Results.Json(state.GetLights())));
		_application.MapGet("/api/lightOn", (Func<HttpRequest, IResult>)((HttpRequest request) => ChangeLight(request, state, isOn: true)));
		_application.MapGet("/api/lightOff", (Func<HttpRequest, IResult>)((HttpRequest request) => ChangeLight(request, state, isOn: false)));
	}

	public async Task StartAsync()
	{
		await _application.StartAsync();
		_started = true;
	}

	public async ValueTask DisposeAsync()
	{
		if (_started)
		{
			await _application.StopAsync();
		}
		await _application.DisposeAsync();
	}

	private static IResult ChangeLight(HttpRequest request, SimulatorState state, bool isOn)
	{
		bool flag = !int.TryParse(request.Query["target"].ToString(), NumberStyles.None, CultureInfo.InvariantCulture, out var result);
		if (!flag)
		{
			bool flag2 = ((result < 1 || result > 4) ? true : false);
			flag = flag2;
		}
		if (flag)
		{
			return Results.BadRequest(new
			{
				error = "target must be an integer from 1 to 4"
			});
		}
		state.SetLight(result, isOn);
		return Results.Json(new
		{
			target = result,
			isOn = isOn
		});
	}
}
