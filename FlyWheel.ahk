;@Ahk2Exe-Base ../v2/AutoHotkey64.exe
#Requires AutoHotkey v2
#SingleInstance Force

; https://www.autohotkey.com/docs/v2/misc/DPIScaling.htm#Workarounds
DllCall("SetThreadDpiAwarenessContext", "ptr", -3, "ptr")

SetKeyDelay(0)
SetWinDelay(0)

CoordMode("Mouse", "Screen")
CoordMode("ToolTip", "Screen")

A_MaxHotkeysPerInterval := 1000

; 休止/再開
SetSuspend(state) {
    Suspend(state)
    if A_IsSuspended {
        TraySetIcon("tray.png",, 1)
        A_TrayMenu.Check("休止/再開")
    } else {
        TraySetIcon("tray.png",, 1)
        A_TrayMenu.Uncheck("休止/再開")
    }
}

; タスクトレイ設定
A_IconTip := "フライホイール"
A_TrayMenu.Delete()
A_TrayMenu.Add("設定ファイル編集", (*) => Run(iniFile))
A_TrayMenu.Add("リロード", (*) => Reload())
A_TrayMenu.Add("休止/再開", (*) => SetSuspend(-1))
A_TrayMenu.Add("終了", (*) => ExitApp())
SetSuspend(0)

; 設定ファイル
iniFile := A_ScriptDir . "\FlyWheel.ini"
iniFileDefault := A_ScriptDir . "\FlyWheel.ini.default"
if (!FileExist(iniFile)) {
    FileCopy(iniFileDefault, iniFile)
}

class FlyWheelApp
{
    ; 設定
    cfg := {}

    ; ホイール履歴
    wheelUpHist := []
    wheelDownHist := []

    ; スクロール情報
    scrollAt := A_TickCount
    stroke := 0
    speed := 0
    line := 0

    ; マウス座標
    x := 0
    y := 0

    ; アイコン
    iconWnd := ""
    iconPic := ""
    iconShown := false
    iconFrame := 0

    ; ツールチップ
    tooltipText := ""

    __New()
    {
        ; 設定ファイル読込
        this.cfg.strokeTimeout := IniRead(iniFile, "Scroll", "StrokeTimeout", 100)
        this.cfg.acceleration := IniRead(iniFile, "Scroll", "Acceleration", 1.30)
        this.cfg.deceleration := IniRead(iniFile, "Scroll", "Deceleration", 0.70)
        this.cfg.maxSpeed := IniRead(iniFile, "Scroll", "MaxSpeed", 300)
        this.cfg.minSpeed := IniRead(iniFile, "Scroll", "MinSpeed", 5)
        this.cfg.nonStopModeStroke := IniRead(iniFile, "Scroll", "NonStopModeStroke", 0)
        this.cfg.reverse := IniRead(iniFile, "Scroll", "Reverse", "false") == "true"
        this.cfg.stopByMouseMove := IniRead(iniFile, "Stop", "MouseMove", "true") == "true"
        this.cfg.stopByLButton := IniRead(iniFile, "Stop", "LButton", "false") == "true"
        this.cfg.stopByRButton := IniRead(iniFile, "Stop", "RButton", "false") == "true"
        this.cfg.stopByMButton := IniRead(iniFile, "Stop", "MButton", "false") == "true"
        this.cfg.showAnimationIcon := IniRead(iniFile, "AnimationIcon", "Enable", "false") == "true"
        this.cfg.showTooltip := IniRead(iniFile, "Tooltip", "Enable", "false") == "true"
    }

    ; 開始
    Start()
    {
        ; スクロールと減速用のタイマーの起動
        SetTimer(() => this.Scroll(), 10)
        SetTimer(() => this.Decelerate(), 100)

        ; アイコン表示
        if (this.cfg.showAnimationIcon) {
            ; -DPIScale https://www.autohotkey.com/docs/v2/misc/DPIScaling.htm#Gui_DPI_Scaling
            ; +E0x02000000(WS_EX_COMPOSITED) +E0x00080000(WS_EX_LAYERED) ちらつき防止
            this.iconWnd := Gui("+AlwaysOnTop +ToolWindow -Caption -DPIScale +E0x02000000 +E0x00080000")
            this.iconPic := this.iconWnd.Add("Picture", "X0 Y0", A_ScriptDir . "\spin.png")
            this.iconWnd.Show("W48 H48 HIDE")
            WinSetRegion("0-0 W48 H48 E", this.iconWnd)
            SetTimer(() => this.UpdateIcon(), 10)
        }

        ; ツールチップ表示
        if (this.cfg.showTooltip) {
            SetTimer(() => this.UpdateTooltip(), 10)
        }
    }

    ; ホイール上回転
    WheelUp()
    {
        this.wheelUpHist := this.WheelSpined(this.wheelUpHist, 1)
    }

    ; ホイール下回転
    WheelDown()
    {
        this.wheelDownHist := this.WheelSpined(this.wheelDownHist, -1)
    }

    ; ホイール回転
    WheelSpined(wheelHist, direction)
    {
        MouseGetPos(&x, &y)
        this.x := x
        this.y := y
        if (this.speed * direction < 0) {
            this.Stop()
        } else {
            this.line += direction
            wheelHist := this.GetSpinSpeed(wheelHist, direction)
            this.Scroll()
        }
        return wheelHist
    }

    ; 回転速度取得
    GetSpinSpeed(wheelHist, direction)
    {
        time := 0
        tickCount := A_TickCount
        newHist := [tickCount]
        Loop wheelHist.Length
        {
            h := wheelHist[A_Index]
            dt := tickCount - h
            if (dt <= this.cfg.strokeTimeout) {
                time += dt
                tickCount := h
                newHist.Push(tickCount)
            } else {
                break
            }
        }
        this.stroke := newHist.Length
        if (this.stroke == 1 || time == 0) {
            this.speed := 0
        } else {
            this.speed := this.stroke / time * 1000
            this.speed *= this.cfg.acceleration ** (this.stroke - 1)
            this.speed := this.speed < this.cfg.maxSpeed ? this.speed : this.cfg.maxSpeed
            this.speed *= direction
        }
        return newHist
    }

    ; スクロール
    Scroll()
    {
        if (this.speed || this.line) {
            if (this.cfg.stopByMouseMove) {
                MouseGetPos(&x, &y)
                prevX := this.x, this.x := x
                prevY := this.y, this.y := y
                if (25 < (this.x - prevX) ** 2 + (this.y - prevY) ** 2) {
                    this.Stop()
                    return
                }
            }
            dt := A_TickCount - this.scrollAt
            this.scrollAt := A_TickCount
            this.line += dt * this.speed / 1000
            notch := this.line < 0 ? Ceil(this.line) : Floor(this.line)
            this.line -= notch
            if (notch) {
                if (this.cfg.reverse) {
                    notch := -notch
                }
                wheel := notch > 0 ? "WheelUp" : "WheelDown"
                count := Abs(notch)
                Send(Format("{Blind}{{1} {2}}", wheel, count))
            }
        }
    }

    ; 減速
    Decelerate()
    {
        if (this.cfg.nonStopModeStroke == 0 || this.stroke < this.cfg.nonStopModeStroke) {
            if (this.speed || this.line) {
                this.speed *= 1 - this.cfg.deceleration ** (this.stroke - 1)
                if (Abs(this.line) < 1 && Abs(this.speed) < this.cfg.minSpeed) {
                    this.Stop()
                }
            }
        }
    }

    ; 停止
    Stop()
    {
        this.stroke := 0
        this.speed := 0
        this.line := 0
    }

    ; アイコン更新
    UpdateIcon()
    {
        if (this.speed) {
            this.iconFrame := Mod(this.iconFrame + 1, 4)
            this.iconPic.Move(this.iconFrame * -48, 0)
            nonStop := this.cfg.nonStopModeStroke && this.cfg.nonStopModeStroke <= this.stroke
            this.iconWnd.BackColor := nonStop ? "FF0000" : "666666"
            MouseGetPos(&x, &y)
            this.iconWnd.Move(x, y)
            if (!this.iconShown) {
                this.iconWnd.Show("NA")
                this.iconShown := true
            }
        } else {
            if (this.iconShown) {
                this.iconWnd.Show("HIDE")
                this.iconShown := false
            }
        }
    }

    ; ツールチップ更新
    UpdateTooltip()
    {
        if (this.speed || this.tooltipText) {
            if (this.speed) {
                arrow := 0 < this.speed ? "▲" : "▼"
                intSpeed := Ceil(Abs(this.speed))
                this.tooltipText := Format("{1}[stroke:{2}][speed:{3}]", arrow, this.stroke, intSpeed)
            } else {
                this.tooltipText := ""
            }
            Tooltip this.tooltipText
        }
    }

}

; 開始
app := FlyWheelApp()
app.Start()

; ホイール回転時の処理
*WheelUp::app.WheelUp()
*WheelDown::app.WheelDown()

; 左ボタンによるスクロール停止
#HotIf (app.cfg.stopByLButton && app.speed)
*LButton::app.Stop()

; 右ボタンによるスクロール停止
#HotIf (app.cfg.stopByRButton && app.speed)
*RButton::app.Stop()

; 中ボタンによるスクロール停止
#HotIf (app.cfg.stopByMButton && app.speed)
*MButton::app.Stop()
