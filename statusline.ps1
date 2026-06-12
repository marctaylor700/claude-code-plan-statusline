param()

$ESC = [char]27

function date_fmt($epoch, $fmt) {
    # Not used directly in PS, handled locally
}

function fmt_time($epoch) {
    if ([string]::IsNullOrEmpty($epoch)) { return '' }
    $n = 0
    if ([long]::TryParse($epoch, [ref]$n)) {
        return [DateTimeOffset]::FromUnixTimeSeconds($n).ToLocalTime().ToString('h:mmtt', [System.Globalization.CultureInfo]::InvariantCulture).ToLowerInvariant()
    }
    return ''
}

function fmt_size($n) {
    if ([string]::IsNullOrEmpty($n)) { return '' }
    $num = 0
    if ([long]::TryParse($n, [ref]$num)) {
        if ($num -ge 1000000) { return "$([math]::Truncate($num / 1000000))M" }
        if ($num -ge 1000) { return "$([math]::Truncate($num / 1000))k" }
        return "$num"
    }
    return ''
}

function fmt_cost($usd) {
    if ([string]::IsNullOrEmpty($usd)) { return '' }
    $num = 0.0
    if ([double]::TryParse($usd, [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$num)) {
        return '$' + $num.ToString('F2', [System.Globalization.CultureInfo]::InvariantCulture)
    }
    return ''
}

function fmt_duration($ms) {
    if ([string]::IsNullOrEmpty($ms)) { return '' }
    $n = 0
    if ([long]::TryParse($ms, [ref]$n)) {
        $s = [math]::Truncate($n / 1000)
        if ($s -ge 3600) { return "$([math]::Truncate($s / 3600))h$([math]::Truncate(($s % 3600) / 60))m" }
        if ($s -ge 60) { return "$([math]::Truncate($s / 60))m$($s % 60)s" }
        return "${s}s"
    }
    return ''
}

function now_epoch() {
    if (-not [string]::IsNullOrEmpty($env:PLAN_SL_NOW)) {
        $n = 0
        if ([long]::TryParse($env:PLAN_SL_NOW, [ref]$n)) { return $n }
    }
    return [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
}

function fmt_when($epoch) {
    if ([string]::IsNullOrEmpty($epoch)) { return '' }
    $n = 0
    if ([long]::TryParse($epoch, [ref]$n)) {
        $now = now_epoch
        $dtEpoch = [DateTimeOffset]::FromUnixTimeSeconds($n).ToLocalTime()
        $dtNow = [DateTimeOffset]::FromUnixTimeSeconds($now).ToLocalTime()

        if ($dtEpoch.ToString('yyyy-MM-dd') -eq $dtNow.ToString('yyyy-MM-dd')) {
            return fmt_time $epoch
        } else {
            return $dtEpoch.ToString('ddd', [System.Globalization.CultureInfo]::InvariantCulture).ToLowerInvariant()
        }
    }
    return ''
}

function truncate_pct($pct) {
    if ([string]::IsNullOrEmpty($pct)) { return '' }
    if ($pct -isnot [string]) { $pct = $pct.ToString() }; $idx = $pct.LastIndexOf('.')
    if ($idx -ge 0) { return $pct.Substring(0, $idx) }
    return $pct
}

function ctx_circle($pctraw) {
    $pct = truncate_pct $pctraw
    if ([string]::IsNullOrEmpty($pct)) { return '' }
    $n = 0
    if ([long]::TryParse($pct, [ref]$n)) {
        if ($n -ge 88) { return '●' }
        if ($n -ge 63) { return '◕' }
        if ($n -ge 38) { return '◑' }
        if ($n -ge 13) { return '◔' }
        return '○'
    }
    return ''
}

function limit_pegged() {
    $five = truncate_pct $script:five_pct
    if (-not [string]::IsNullOrEmpty($five)) {
        $n = 0; if ([long]::TryParse($five, [ref]$n) -and $n -ge 100) { return $true }
    }
    $week = truncate_pct $script:week_pct
    if (-not [string]::IsNullOrEmpty($week)) {
        $n = 0; if ([long]::TryParse($week, [ref]$n) -and $n -ge 100) { return $true }
    }
    return $false
}

function render_name($text) {
    if ([string]::IsNullOrEmpty($text)) { return '' }
    if (limit_pegged) {
        return "${ESC}[2m${text}${ESC}[0m"
    }
    if (-not [string]::IsNullOrEmpty($script:NAME_SGR)) {
        return "${ESC}[$($script:NAME_SGR)m${text}${ESC}[0m"
    }
    return $text
}

function Theme-Default() {
    $script:TIER_CALM = '32'; $script:TIER_WARN = '33'; $script:TIER_HOT = '38;5;208'; $script:TIER_URGENT = '31'
    $script:NAME_SGR = '1'
    $script:SEP = ' │ '; $script:SEP_COLOR = ''
    $script:META = ''
    $script:SEG_CIRCLE = 0; $script:LABEL_SEP = ':'
    $script:CIRCLE_SGR = '@tier'; $script:LABEL_SGR = '@tier'
    $script:EGG_GLYPH = ''; $script:EGG_GLYPH_COLOR = ''
    $script:EGG_MSG_A = '100% 💀'; $script:EGG_COLOR_A = '31'
    $script:EGG_MSG_B = '100% 💀'; $script:EGG_COLOR_B = '31'
    $script:EGG_RESET_WORD = 'respawn'
}

function Theme-Hearth() {
    $script:TIER_CALM = ''; $script:TIER_WARN = ''; $script:TIER_HOT = '38;5;208'; $script:TIER_URGENT = '1;38;5;196'
    $script:NAME_SGR = '1;38;5;214'
    $script:SEP = ' · '; $script:SEP_COLOR = '2'
    $script:META = '2;3'
    $script:SEG_CIRCLE = 1; $script:LABEL_SEP = ''
    $script:CIRCLE_SGR = '38;5;214'; $script:LABEL_SGR = ''
    $script:EGG_GLYPH = '○'; $script:EGG_GLYPH_COLOR = '2'
    $script:EGG_MSG_A = 'burnt out'; $script:EGG_COLOR_A = '1;38;5;196'
    $script:EGG_MSG_B = 'burnt out'; $script:EGG_COLOR_B = '1;38;5;196'
    $script:EGG_RESET_WORD = 'rekindles'
}

function Theme-Glow() {
    $script:TIER_CALM = '1;38;5;41'; $script:TIER_WARN = '1;38;5;205'; $script:TIER_HOT = '1;38;5;199'; $script:TIER_URGENT = '1;38;5;197'
    $script:NAME_SGR = '1;38;5;199'
    $script:SEP = ' · '; $script:SEP_COLOR = '2'
    $script:META = '3;38;5;175'
    $script:SEG_CIRCLE = 1; $script:LABEL_SEP = ''
    $script:CIRCLE_SGR = '@tier'; $script:LABEL_SGR = '@tier'
    $script:EGG_GLYPH = ''; $script:EGG_GLYPH_COLOR = ''
    $script:EGG_MSG_A = 'GAME OVER'; $script:EGG_COLOR_A = '1;38;5;197'
    $script:EGG_MSG_B = 'INSERT COIN'; $script:EGG_COLOR_B = '1;38;5;199'
    $script:EGG_RESET_WORD = '1UP'
}

function Theme-Scrubs() {
    $script:TIER_CALM = '38;5;30'; $script:TIER_WARN = '1;38;5;37'; $script:TIER_HOT = '38;5;214'; $script:TIER_URGENT = '1;38;5;196'
    $script:NAME_SGR = '1;38;5;37'
    $script:SEP = ' · '; $script:SEP_COLOR = '2'
    $script:META = '3;38;5;152'
    $script:SEG_CIRCLE = 1; $script:LABEL_SEP = ''
    $script:CIRCLE_SGR = '@tier'; $script:LABEL_SGR = '@tier'
    $script:EGG_GLYPH = ''; $script:EGG_GLYPH_COLOR = ''
    $script:EGG_MSG_A = 'CODE BLUE'; $script:EGG_COLOR_A = '1;38;5;196'
    $script:EGG_MSG_B = '▁▁▁▁▁▁▁▁▁'; $script:EGG_COLOR_B = '1;38;5;196'
    $script:EGG_RESET_WORD = 'defib'
}

function paint($sgr, $text) {
    if (-not [string]::IsNullOrEmpty($sgr)) {
        return "${ESC}[${sgr}m${text}${ESC}[0m"
    }
    return $text
}

function paint_sep() {
    return paint $script:SEP_COLOR $script:SEP
}

function tier_color($pctraw) {
    $pct = truncate_pct $pctraw
    if ([string]::IsNullOrEmpty($pct)) { return '' }
    $n = 0
    if ([long]::TryParse($pct, [ref]$n)) {
        if ($n -ge 90) { return $script:TIER_URGENT }
        if ($n -ge 70) { return $script:TIER_HOT }
        if ($n -ge 50) { return $script:TIER_WARN }
        return $script:TIER_CALM
    }
    return ''
}

function cost_tier_color($usd) {
    if ([string]::IsNullOrEmpty($usd)) { return '' }
    $dollars = truncate_pct $usd
    if ([string]::IsNullOrEmpty($dollars)) { $dollars = '0' }
    $n = 0
    if ([long]::TryParse($dollars, [ref]$n)) {
        if ($n -ge 10) { return $script:TIER_URGENT }
        if ($n -ge 5) { return $script:TIER_HOT }
        if ($n -ge 2) { return $script:TIER_WARN }
        return $script:TIER_CALM
    }
    return ''
}

function meta_sgr($tier) {
    if (-not [string]::IsNullOrEmpty($script:META)) { return $script:META }
    return $tier
}

function span_sgr($sgr, $tier) {
    if ($sgr -eq '@tier') { return $tier }
    return $sgr
}

function seg_rate($label, $pctraw, $reset_str) {
    $pct = truncate_pct $pctraw
    $n = 0
    if ([long]::TryParse($pct, [ref]$n) -and $n -ge 100) {
        return egg $label $reset_str
    }

    $tier = tier_color $pct
    $res = ""
    if ($script:SEG_CIRCLE -eq 1) {
        $res += paint (span_sgr $script:CIRCLE_SGR $tier) (ctx_circle $pct)
        $res += ' '
    }
    $res += paint (span_sgr $script:LABEL_SGR $tier) "${label}$($script:LABEL_SEP)"
    $res += ' '
    $res += paint $tier "${pct}%"
    $res += ' '
    $res += paint (meta_sgr '') "(→${reset_str})"
    return $res
}

function seg_ctx($pctraw, $size) {
    $pct = truncate_pct $pctraw
    $tier = tier_color $pct
    $res = ""
    $res += paint (span_sgr $script:CIRCLE_SGR $tier) (ctx_circle $pct)
    $res += ' '
    $res += paint $tier "${pct}%"
    if (-not [string]::IsNullOrEmpty($size)) {
        $res += paint (meta_sgr $tier) $size
    }
    return $res
}

function egg($label, $reset_str) {
    $now = now_epoch
    $msg = ""
    $col = ""
    if (($now % 2 -eq 1) -and ($script:EGG_MSG_A -ne $script:EGG_MSG_B)) {
        $msg = $script:EGG_MSG_B
        $col = $script:EGG_COLOR_B
    } else {
        $msg = $script:EGG_MSG_A
        $col = $script:EGG_COLOR_A
    }

    $res = ""
    if (-not [string]::IsNullOrEmpty($script:EGG_GLYPH)) {
        $res += "${ESC}[$($script:EGG_GLYPH_COLOR)m$($script:EGG_GLYPH)${ESC}[0m "
    }

    $lblcol = ""
    if (-not [string]::IsNullOrEmpty($script:LABEL_SGR)) {
        $lblcol = $col
    }

    $res += paint $lblcol "${label}$($script:LABEL_SEP)"
    $res += ' '
    $res += paint $col $msg
    $res += ' '

    if (-not [string]::IsNullOrEmpty($script:META)) {
        $res += paint $script:META "($($script:EGG_RESET_WORD) →${reset_str})"
    } else {
        $res += "($($script:EGG_RESET_WORD) →${reset_str})"
    }
    return $res
}

function render_line() {
    if ([string]::IsNullOrEmpty($script:ctx_pct) -and [string]::IsNullOrEmpty($script:five_pct) -and [string]::IsNullOrEmpty($script:week_pct) -and [string]::IsNullOrEmpty($script:cost_usd)) {
        $res = render_name $script:model
        $res += paint_sep
        $res += paint $script:META 'usage data pending - make a request'
        return $res
    }

    $res = render_name $script:model

    if ((-not [string]::IsNullOrEmpty($script:five_pct)) -or (-not [string]::IsNullOrEmpty($script:week_pct))) {
        if (-not [string]::IsNullOrEmpty($script:five_pct)) {
            $res += paint_sep
            $res += seg_rate '5h' $script:five_pct (fmt_time $script:five_reset)
        }
        if (-not [string]::IsNullOrEmpty($script:week_pct)) {
            $res += paint_sep
            $res += seg_rate 'week' $script:week_pct (fmt_when $script:week_reset)
        }
    } else {
        if (-not [string]::IsNullOrEmpty($script:cost_usd)) {
            $res += paint_sep
            $res += paint (cost_tier_color $script:cost_usd) (fmt_cost $script:cost_usd)
        }
        if (-not [string]::IsNullOrEmpty($script:dur_ms)) {
            $res += paint_sep
            $res += paint (meta_sgr '') (fmt_duration $script:dur_ms)
        }
        if ((-not [string]::IsNullOrEmpty($script:lines_added)) -or (-not [string]::IsNullOrEmpty($script:lines_removed))) {
            $res += paint_sep
            $la = if ([string]::IsNullOrEmpty($script:lines_added)) { '0' } else { $script:lines_added }
            $lr = if ([string]::IsNullOrEmpty($script:lines_removed)) { '0' } else { $script:lines_removed }
            $res += paint (meta_sgr '') "+${la}/-${lr}"
        }
        if ((-not [string]::IsNullOrEmpty($script:in_tokens)) -or (-not [string]::IsNullOrEmpty($script:out_tokens))) {
            $res += paint_sep
            $it = if ([string]::IsNullOrEmpty($script:in_tokens)) { '0' } else { $script:in_tokens }
            $ot = if ([string]::IsNullOrEmpty($script:out_tokens)) { '0' } else { $script:out_tokens }
            $res += paint (meta_sgr '') "$(fmt_size $it)↑ $(fmt_size $ot)↓"
        }
    }

    if (-not [string]::IsNullOrEmpty($script:ctx_pct)) {
        $size = ""
        if (-not [string]::IsNullOrEmpty($script:ctx_size)) {
            $size = " of $(fmt_size $script:ctx_size)"
        }
        $res += paint_sep
        $res += seg_ctx $script:ctx_pct $size
    }

    return $res
}

function Main() {
    $inputRaw = [Console]::In.ReadToEnd()

    $script:model = 'Claude'
    $script:five_pct = ''
    $script:five_reset = ''
    $script:week_pct = ''
    $script:week_reset = ''
    $script:ctx_pct = ''
    $script:ctx_size = ''
    $script:cost_usd = ''
    $script:dur_ms = ''
    $script:lines_added = ''
    $script:lines_removed = ''
    $script:in_tokens = ''
    $script:out_tokens = ''

    $parsed = $null
    try {
        if (-not [string]::IsNullOrWhiteSpace($inputRaw)) {
            $parsed = ConvertFrom-Json $inputRaw -ErrorAction Stop
        }
    } catch {
        $parsed = $null
    }

    if ($null -ne $parsed) {
        $m = 'Claude'
        if ($null -ne $parsed.model) {
            if ($null -ne $parsed.model.display_name) { $m = $parsed.model.display_name }
            elseif ($null -ne $parsed.model.id) { $m = $parsed.model.id }
        }
        $script:model = $m.ToString([System.Globalization.CultureInfo]::InvariantCulture)

        if ($null -ne $parsed.rate_limits) {
            if ($null -ne $parsed.rate_limits.five_hour) {
                if ($null -ne $parsed.rate_limits.five_hour.used_percentage) { $script:five_pct = $parsed.rate_limits.five_hour.used_percentage.ToString([System.Globalization.CultureInfo]::InvariantCulture) }
                if ($null -ne $parsed.rate_limits.five_hour.resets_at) { $script:five_reset = $parsed.rate_limits.five_hour.resets_at.ToString([System.Globalization.CultureInfo]::InvariantCulture) }
            }
            if ($null -ne $parsed.rate_limits.seven_day) {
                if ($null -ne $parsed.rate_limits.seven_day.used_percentage) { $script:week_pct = $parsed.rate_limits.seven_day.used_percentage.ToString([System.Globalization.CultureInfo]::InvariantCulture) }
                if ($null -ne $parsed.rate_limits.seven_day.resets_at) { $script:week_reset = $parsed.rate_limits.seven_day.resets_at.ToString([System.Globalization.CultureInfo]::InvariantCulture) }
            }
        }
        if ($null -ne $parsed.context_window) {
            if ($null -ne $parsed.context_window.used_percentage) { $script:ctx_pct = $parsed.context_window.used_percentage.ToString([System.Globalization.CultureInfo]::InvariantCulture) }
            if ($null -ne $parsed.context_window.context_window_size) { $script:ctx_size = $parsed.context_window.context_window_size.ToString([System.Globalization.CultureInfo]::InvariantCulture) }
            if ($null -ne $parsed.context_window.total_input_tokens) { $script:in_tokens = $parsed.context_window.total_input_tokens.ToString([System.Globalization.CultureInfo]::InvariantCulture) }
            if ($null -ne $parsed.context_window.total_output_tokens) { $script:out_tokens = $parsed.context_window.total_output_tokens.ToString([System.Globalization.CultureInfo]::InvariantCulture) }
        }
        if ($null -ne $parsed.cost) {
            if ($null -ne $parsed.cost.total_cost_usd) { $script:cost_usd = $parsed.cost.total_cost_usd.ToString([System.Globalization.CultureInfo]::InvariantCulture) }
            if ($null -ne $parsed.cost.total_duration_ms) { $script:dur_ms = $parsed.cost.total_duration_ms.ToString([System.Globalization.CultureInfo]::InvariantCulture) }
            if ($null -ne $parsed.cost.total_lines_added) { $script:lines_added = $parsed.cost.total_lines_added.ToString([System.Globalization.CultureInfo]::InvariantCulture) }
            if ($null -ne $parsed.cost.total_lines_removed) { $script:lines_removed = $parsed.cost.total_lines_removed.ToString([System.Globalization.CultureInfo]::InvariantCulture) }
        }
    }

    $theme = 'default'
    $homeDir = if (-not [string]::IsNullOrEmpty($env:HOME)) { $env:HOME } else { $env:USERPROFILE }
    $configFile = "$homeDir/.claude/plan-statusline.conf"

    if (Test-Path $configFile -PathType Leaf) {
        try {
            $lines = Get-Content $configFile -ErrorAction SilentlyContinue
            if ($null -ne $lines) {
                foreach ($line in $lines) {
                    $idx = $line.IndexOf('=')
                    if ($idx -ge 0) {
                        $key = $line.Substring(0, $idx).Replace(' ', '')
                        $value = $line.Substring($idx + 1).Replace(' ', '')
                        if ($value.EndsWith('"')) { $value = $value.Substring(0, $value.Length - 1) }
                        if ($value.StartsWith('"')) { $value = $value.Substring(1) }
                        if ($key -eq 'theme' -and -not [string]::IsNullOrEmpty($value)) {
                            $theme = $value
                        }
                    }
                }
            }
        } catch {}
    }

    switch ($theme) {
        'hearth' { Theme-Hearth }
        'glow' { Theme-Glow }
        'scrubs' { Theme-Scrubs }
        default { Theme-Default }
    }

    $lineOut = render_line

    try {
        [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
    } catch {}
    [Console]::Out.Write($lineOut)
}

if ($MyInvocation.InvocationName -ne '.') {
    Main
}
