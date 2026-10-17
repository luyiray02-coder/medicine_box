using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.Linq;
using System.Windows.Forms;

namespace TrayApiSimulator;

internal sealed class MainForm : Form
{
	private sealed class LightButton : Button
	{
		private bool _isOn;

		[DesignerSerializationVisibility(DesignerSerializationVisibility.Hidden)]
		public bool IsOn
		{
			get
			{
				return _isOn;
			}
			set
			{
				_isOn = value;
				Invalidate();
			}
		}

		public LightButton()
		{
			SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, value: true);
		}

		protected override void OnPaint(PaintEventArgs e)
		{
			e.Graphics.Clear(base.Parent?.BackColor ?? Color.White);
			e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
			Rectangle rect = new Rectangle(2, 2, base.Width - 5, base.Height - 5);
			using SolidBrush brush = new SolidBrush(_isOn ? Green : Off);
			using Pen pen = new Pen(_isOn ? Color.FromArgb(83, 145, 50) : Color.FromArgb(190, 198, 204));
			e.Graphics.FillEllipse(brush, rect);
			e.Graphics.DrawEllipse(pen, rect);
			if (Focused)
			{
				ControlPaint.DrawFocusRectangle(e.Graphics, base.ClientRectangle);
			}
		}
	}

	private const string ApiBaseUrl = "https://localhost:8080";

	private static readonly Color Ink = Color.FromArgb(39, 45, 52);

	private static readonly Color Muted = Color.FromArgb(98, 106, 114);

	private static readonly Color Green = Color.FromArgb(105, 172, 69);

	private static readonly Color Off = Color.FromArgb(226, 231, 235);

	private readonly SimulatorState _state;

	private readonly TextBox[] _weightInputs = new TextBox[4];

	private readonly TextBox _temperatureInput;

	private readonly TextBox _humidityInput;

	private readonly LightButton[] _lightButtons = new LightButton[4];

	private readonly Label _feedback;

	private readonly ToolTip _toolTip = new ToolTip();

	public MainForm(SimulatorState state, string? apiStartupError)
	{
		_state = state;
		Text = "藥盤 API 模擬工具";
		base.ClientSize = new Size(640, Math.Min(825, (Screen.PrimaryScreen?.WorkingArea.Height ?? 900) - 90));
		AutoScroll = true;
		base.AutoScrollMinSize = new Size(0, 815);
		base.StartPosition = FormStartPosition.CenterScreen;
		base.FormBorderStyle = FormBorderStyle.FixedSingle;
		base.MaximizeBox = false;
		base.AutoScaleMode = AutoScaleMode.Dpi;
		BackColor = Color.FromArgb(247, 249, 251);
		Font = new Font("Microsoft JhengHei UI", 10f);
		base.Controls.Add(CreateLabel("藥盤 API 模擬工具", 28, 24, 584, 38, 17f, bold: true));
		Label label = CreateLabel("修改數值後按「套用參數」；點選燈號可切換狀態。", 29, 67, 584, 26, 9.5f);
		label.ForeColor = Muted;
		base.Controls.Add(label);
		Panel panel = CreateCard(28, 105, 584, 232);
		panel.Controls.Add(CreateLabel("藥盤重量（g）", 22, 16, 250, 27, 11f, bold: true));
		for (int i = 0; i < 4; i++)
		{
			int x = 22 + i * 137;
			panel.Controls.Add(CreateLabel($"藥盤 {i + 1}", x, 50, 118, 26, 10f));
			_weightInputs[i] = CreateInput(x, 79, 118, "0");
			panel.Controls.Add(_weightInputs[i]);
		}
		panel.Controls.Add(CreateLabel("目前溫度（°C）", 22, 136, 160, 27, 10f));
		_temperatureInput = CreateInput(22, 166, 160, "28");
		panel.Controls.Add(_temperatureInput);
		panel.Controls.Add(CreateLabel("目前濕度（%）", 206, 136, 160, 27, 10f));
		_humidityInput = CreateInput(206, 166, 160, "60");
		panel.Controls.Add(_humidityInput);
		Button button = new Button
		{
			Text = "套用參數",
			Location = new Point(410, 164),
			Size = new Size(151, 38),
			BackColor = Color.FromArgb(42, 106, 181),
			ForeColor = Color.White,
			FlatStyle = FlatStyle.Flat,
			Font = new Font(Font, FontStyle.Bold),
			Cursor = Cursors.Hand
		};
		button.FlatAppearance.BorderSize = 0;
		button.Click += ApplyButton_Click;
		panel.Controls.Add(button);
		base.Controls.Add(panel);
		_feedback = CreateLabel("", 29, 342, 584, 27, 9f);
		base.Controls.Add(_feedback);
		Panel panel2 = CreateCard(28, 377, 584, 108);
		panel2.Controls.Add(CreateLabel("燈號狀態", 22, 13, 200, 27, 11f, bold: true));
		Label label2 = CreateLabel("點選圓燈切換", 413, 17, 147, 22, 9f);
		label2.ForeColor = Muted;
		label2.TextAlign = ContentAlignment.MiddleRight;
		panel2.Controls.Add(label2);
		for (int j = 0; j < 4; j++)
		{
			int target = j + 1;
			int num = 29 + j * 137;
			LightButton lightButton = new LightButton
			{
				Location = new Point(num, 56),
				Size = new Size(32, 32),
				Cursor = Cursors.Hand,
				TabStop = true,
				AccessibleName = $"切換藥盤 {target} 燈號"
			};
			lightButton.Click += delegate
			{
				_state.ToggleLight(target);
			};
			_lightButtons[j] = lightButton;
			panel2.Controls.Add(lightButton);
			panel2.Controls.Add(CreateLabel($"藥盤 {target}", num + 40, 57, 88, 29, 10f));
		}
		base.Controls.Add(panel2);
		Panel panel3 = CreateCard(28, 500, 584, 92);
		panel3.Controls.Add(CreateLabel("API 狀態", 22, 11, 150, 26, 11f, bold: true));
		Label label3 = CreateLabel("", 22, 41, 538, 40, 9.5f);
		label3.ForeColor = ((apiStartupError == null) ? Color.FromArgb(50, 125, 55) : Color.FromArgb(177, 37, 37));
		label3.Text = ((apiStartupError == null) ? "運作中  https://localhost:8080" : ("啟動失敗：" + apiStartupError));
		label3.AutoEllipsis = true;
		_toolTip.SetToolTip(label3, label3.Text);
		panel3.Controls.Add(label3);
		base.Controls.Add(panel3);
		Panel panel4 = CreateCard(28, 607, 584, 190);
		panel4.Controls.Add(CreateLabel("可用 API", 22, 11, 180, 27, 11f, bold: true));
		Label label4 = CreateLabel("點擊開啟；target 可填 1–4", 270, 14, 290, 23, 9f);
		label4.ForeColor = Muted;
		label4.TextAlign = ContentAlignment.MiddleRight;
		panel4.Controls.Add(label4);
		(string, string)[] array = new(string, string)[5]
		{
			("/api/weight", "取得四盤重量"),
			("/api/status", "取得溫度、濕度"),
			("/api/lightStatus", "取得四個燈號狀態"),
			("/api/lightOn?target=1", "開啟指定燈號"),
			("/api/lightOff?target=1", "關閉指定燈號")
		};
		for (int num2 = 0; num2 < array.Length; num2++)
		{
			int y = 44 + num2 * 27;
			panel4.Controls.Add(CreateLabel("GET", 22, y, 34, 24, 9f));
			string text = "https://localhost:8080" + array[num2].Item1;
			LinkLabel linkLabel = new LinkLabel
			{
				Text = text,
				Location = new Point(58, y),
				Size = new Size(373, 24),
				Font = new Font("Consolas", 9f),
				LinkBehavior = LinkBehavior.HoverUnderline,
				LinkColor = Color.FromArgb(31, 91, 166),
				TextAlign = ContentAlignment.MiddleLeft,
				Cursor = Cursors.Hand
			};
			linkLabel.Links.Add(0, text.Length, text);
			linkLabel.LinkClicked += ApiLink_LinkClicked;
			panel4.Controls.Add(linkLabel);
			Label label5 = CreateLabel(array[num2].Item2, 440, y, 120, 24, 9f);
			label5.ForeColor = Muted;
			panel4.Controls.Add(label5);
		}
		base.Controls.Add(panel4);
		_state.LightChanged += State_LightChanged;
		RefreshLightButtons();
	}

	protected override void OnShown(EventArgs e)
	{
		base.OnShown(e);
		RefreshLightButtons();
	}

	protected override void OnFormClosed(FormClosedEventArgs e)
	{
		_state.LightChanged -= State_LightChanged;
		_toolTip.Dispose();
		base.OnFormClosed(e);
	}

	private static Panel CreateCard(int x, int y, int width, int height)
	{
		return new Panel
		{
			Location = new Point(x, y),
			Size = new Size(width, height),
			BackColor = Color.White,
			BorderStyle = BorderStyle.FixedSingle
		};
	}

	private static Label CreateLabel(string text, int x, int y, int width, int height, float fontSize, bool bold = false)
	{
		return new Label
		{
			Text = text,
			Location = new Point(x, y),
			Size = new Size(width, height),
			ForeColor = Ink,
			Font = new Font("Microsoft JhengHei UI", fontSize, bold ? FontStyle.Bold : FontStyle.Regular),
			TextAlign = ContentAlignment.MiddleLeft
		};
	}

	private static TextBox CreateInput(int x, int y, int width, string initialValue)
	{
		return new TextBox
		{
			Location = new Point(x, y),
			Size = new Size(width, 34),
			Text = initialValue,
			BorderStyle = BorderStyle.FixedSingle,
			Font = new Font("Microsoft JhengHei UI", 11f),
			TextAlign = HorizontalAlignment.Right
		};
	}

	private void ApiLink_LinkClicked(object? sender, LinkLabelLinkClickedEventArgs e)
	{
		if (!(e.Link?.LinkData is string fileName))
		{
			return;
		}
		try
		{
			Process.Start(new ProcessStartInfo(fileName)
			{
				UseShellExecute = true
			});
			if (sender is LinkLabel linkLabel)
			{
				linkLabel.LinkVisited = true;
			}
		}
		catch (Exception ex)
		{
			MessageBox.Show(this, "無法開啟瀏覽器：" + ex.Message, "開啟 API 失敗", MessageBoxButtons.OK, MessageBoxIcon.Hand);
		}
	}

	private void ApplyButton_Click(object? sender, EventArgs e)
	{
		foreach (TextBox item in _weightInputs.Append(_temperatureInput).Append(_humidityInput))
		{
			item.BackColor = Color.White;
		}
		decimal[] array = new decimal[4];
		for (int i = 0; i < array.Length; i++)
		{
			if (!TryReadDecimal(_weightInputs[i], out array[i]) || array[i] < 0m)
			{
				ShowInputError(_weightInputs[i], $"藥盤 {i + 1} 重量必須是 0 以上的數字。");
				return;
			}
		}
		if (!TryReadDecimal(_temperatureInput, out var value))
		{
			ShowInputError(_temperatureInput, "溫度必須是有效數字。");
			return;
		}
		bool flag = !TryReadDecimal(_humidityInput, out var value2);
		if (!flag)
		{
			bool flag2 = ((value2 < 0m || value2 > 100m) ? true : false);
			flag = flag2;
		}
		if (flag)
		{
			ShowInputError(_humidityInput, "濕度必須是 0 到 100 之間的數字。");
			return;
		}
		_state.SetMeasurements(array, value, value2);
		_feedback.ForeColor = Color.FromArgb(50, 125, 55);
		_feedback.Text = "參數已套用，API 將回傳最新數值。";
	}

	private static bool TryReadDecimal(TextBox input, out decimal value)
	{
		if (!decimal.TryParse(input.Text, NumberStyles.Integer | NumberStyles.AllowDecimalPoint, CultureInfo.CurrentCulture, out value))
		{
			return decimal.TryParse(input.Text, NumberStyles.Integer | NumberStyles.AllowDecimalPoint, CultureInfo.InvariantCulture, out value);
		}
		return true;
	}

	private void ShowInputError(TextBox input, string message)
	{
		input.BackColor = Color.FromArgb(255, 232, 232);
		input.Focus();
		input.SelectAll();
		_feedback.ForeColor = Color.FromArgb(177, 37, 37);
		_feedback.Text = message;
	}

	private void State_LightChanged(object? sender, LightChangedEventArgs e)
	{
		if (base.IsDisposed || !base.IsHandleCreated)
		{
			return;
		}
		if (!base.InvokeRequired)
		{
			RefreshLightButtons();
			return;
		}
		try
		{
			BeginInvoke(RefreshLightButtons);
		}
		catch (InvalidOperationException)
		{
		}
	}

	private void RefreshLightButtons()
	{
		bool[] lights = _state.GetLights();
		for (int i = 0; i < lights.Length; i++)
		{
			RenderLight(i + 1, lights[i]);
		}
	}

	private void RenderLight(int target, bool isOn)
	{
		if (!base.IsDisposed)
		{
			LightButton lightButton = _lightButtons[target - 1];
			lightButton.IsOn = isOn;
			_toolTip.SetToolTip(lightButton, $"藥盤 {target}：{(isOn ? "開" : "關")}，點選切換");
		}
	}
}
