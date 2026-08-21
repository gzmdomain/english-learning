param(
  [Parameter(Mandatory = $true)]
  [string]$InputPath,
  [string]$AudioOutput = "",
  [string]$TrackOutput = "",
  [string]$VoiceName = "Microsoft Zira Desktop",
  [int]$VoiceRate = -1
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $AudioOutput) {
  $AudioOutput = Join-Path $repoRoot "audio\scim-first-60-days-zira.wav"
}
if (-not $TrackOutput) {
  $TrackOutput = Join-Path $repoRoot "data\scim-first-60-days-track.js"
}

Add-Type -AssemblyName System.Speech

function Get-WordCount {
  param([string]$Text)
  return ([regex]::Matches($Text, "[A-Za-z0-9]+(?:['-][A-Za-z0-9]+)?")).Count
}

function Split-LongSentence {
  param([string]$Text)

  $clean = ($Text -replace "\s+", " ").Trim()
  if ((Get-WordCount $clean) -le 34) {
    return @($clean)
  }

  $clauses = [regex]::Matches($clean, "[^,;:—]+[,;:—]?") |
    ForEach-Object { $_.Value.Trim() } |
    Where-Object { $_ }
  if ($clauses.Count -le 1) {
    return @($clean)
  }

  $chunks = [System.Collections.Generic.List[string]]::new()
  $buffer = ""
  foreach ($clause in $clauses) {
    $candidate = if ($buffer) { "$buffer $clause" } else { $clause }
    if ($buffer -and (Get-WordCount $candidate) -gt 28) {
      $chunks.Add($buffer.Trim())
      $buffer = $clause
    } else {
      $buffer = $candidate
    }
  }
  if ($buffer) {
    $chunks.Add($buffer.Trim())
  }

  return $chunks.ToArray()
}

function Split-LineIntoSegments {
  param([string]$Line)

  $sentences = [regex]::Matches(
    ($Line -replace "\s+", " ").Trim(),
    '[^.!?]+[.!?]+|[^.!?]+$'
  ) | ForEach-Object { $_.Value.Trim() } | Where-Object { $_ }

  $result = [System.Collections.Generic.List[string]]::new()
  foreach ($sentence in $sentences) {
    foreach ($chunk in (Split-LongSentence $sentence)) {
      if ($chunk) {
        $result.Add($chunk)
      }
    }
  }
  return $result.ToArray()
}

function Convert-ToSpeechText {
  param([string]$Text)

  $speech = $Text
  $speech = $speech -replace "\bFY27 H1\b", "fiscal year twenty seven, first half"
  $speech = $speech -replace "\bFY26\b", "fiscal year twenty six"
  $speech = $speech -replace "\bFY27\b", "fiscal year twenty seven"
  $speech = $speech -replace "\b25\.4K\b", "twenty five point four thousand"
  $speech = $speech -replace "\b90\.3%\b", "ninety point three percent"
  $speech = $speech -replace "\b732\b", "seven hundred thirty two"
  $speech = $speech -replace "\bSCIM\b", "skim"
  $speech = $speech -replace "\bVDM\b", "V D M"
  $speech = $speech -replace "\bCSAT\b", "C sat"
  $speech = $speech -replace "\bDSAT\b", "D sat"
  $speech = $speech -replace "\bAI\b", "A I"
  return $speech
}

function Get-WaveData {
  param([string]$Path)

  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -lt 44 -or [Text.Encoding]::ASCII.GetString($bytes, 0, 4) -ne "RIFF") {
    throw "Invalid WAV file: $Path"
  }

  $offset = 12
  while ($offset + 8 -le $bytes.Length) {
    $chunkId = [Text.Encoding]::ASCII.GetString($bytes, $offset, 4)
    $chunkSize = [BitConverter]::ToInt32($bytes, $offset + 4)
    $dataOffset = $offset + 8
    if ($chunkId -eq "data") {
      $data = [byte[]]::new($chunkSize)
      [Array]::Copy($bytes, $dataOffset, $data, 0, $chunkSize)
      return $data
    }
    $offset = $dataOffset + $chunkSize + ($chunkSize % 2)
  }

  throw "WAV data chunk not found: $Path"
}

function Write-PcmWave {
  param(
    [string]$Path,
    [byte[]]$Data,
    [int]$SampleRate = 24000,
    [int]$Channels = 1,
    [int]$BitsPerSample = 16
  )

  $directory = Split-Path -Parent $Path
  [System.IO.Directory]::CreateDirectory($directory) | Out-Null

  $blockAlign = [int]($Channels * $BitsPerSample / 8)
  $byteRate = $SampleRate * $blockAlign
  $stream = [System.IO.File]::Create($Path)
  $writer = [System.IO.BinaryWriter]::new($stream)
  try {
    $writer.Write([Text.Encoding]::ASCII.GetBytes("RIFF"))
    $writer.Write([int](36 + $Data.Length))
    $writer.Write([Text.Encoding]::ASCII.GetBytes("WAVE"))
    $writer.Write([Text.Encoding]::ASCII.GetBytes("fmt "))
    $writer.Write([int]16)
    $writer.Write([int16]1)
    $writer.Write([int16]$Channels)
    $writer.Write([int]$SampleRate)
    $writer.Write([int]$byteRate)
    $writer.Write([int16]$blockAlign)
    $writer.Write([int16]$BitsPerSample)
    $writer.Write([Text.Encoding]::ASCII.GetBytes("data"))
    $writer.Write([int]$Data.Length)
    $writer.Write($Data)
  } finally {
    $writer.Dispose()
    $stream.Dispose()
  }
}

function Get-Phonetic {
  param([string]$Word)

  try {
    $encoded = [Uri]::EscapeDataString($Word)
    $response = Invoke-RestMethod -Uri "https://api.dictionaryapi.dev/api/v2/entries/en/$encoded" -TimeoutSec 15
    $entry = $response[0]
    if ($entry.phonetic) {
      return [string]$entry.phonetic
    }
    $phonetic = $entry.phonetics | Where-Object { $_.text } | Select-Object -First 1
    if ($phonetic) {
      return [string]$phonetic.text
    }
  } catch {
    return ""
  }
  return ""
}

$headings = [System.Collections.Generic.HashSet[string]]::new(
  [string[]]@(
    "Progress So Far",
    "Investing in People and Culture",
    "Scaling AI",
    "Looking Ahead - Building the Culture We Need",
    "A Final Thought"
  ),
  [StringComparer]::OrdinalIgnoreCase
)
$skipLines = [System.Collections.Generic.HashSet[string]]::new(
  [string[]]@("Aged Backlog", "Created vs Closed Volume"),
  [StringComparer]::OrdinalIgnoreCase
)

$displaySegments = [System.Collections.Generic.List[object]]::new()
foreach ($rawLine in (Get-Content -LiteralPath $InputPath)) {
  $line = ($rawLine -replace "\s+", " ").Trim()
  if (-not $line -or $skipLines.Contains($line)) {
    continue
  }

  if ($headings.Contains($line)) {
    $displaySegments.Add([ordered]@{
      text = "$line."
      heading = $true
    })
    continue
  }

  foreach ($segment in (Split-LineIntoSegments $line)) {
    $displaySegments.Add([ordered]@{
      text = $segment
      heading = $false
    })
  }
}

$sampleRate = 24000
$bitsPerSample = 16
$channels = 1
$bytesPerSecond = $sampleRate * $channels * ($bitsPerSample / 8)
$audioStream = [System.IO.MemoryStream]::new()
$timedSegments = [System.Collections.Generic.List[object]]::new()
$tempDirectory = Join-Path $env:TEMP ("scim-tts-" + [Guid]::NewGuid().ToString("N"))
[System.IO.Directory]::CreateDirectory($tempDirectory) | Out-Null

$synth = [System.Speech.Synthesis.SpeechSynthesizer]::new()
$synth.SelectVoice($VoiceName)
$synth.Rate = $VoiceRate
$format = [System.Speech.AudioFormat.SpeechAudioFormatInfo]::new(
  $sampleRate,
  [System.Speech.AudioFormat.AudioBitsPerSample]::Sixteen,
  [System.Speech.AudioFormat.AudioChannel]::Mono
)

try {
  for ($index = 0; $index -lt $displaySegments.Count; $index++) {
    $item = $displaySegments[$index]
    $tempWave = Join-Path $tempDirectory ("segment-{0:D4}.wav" -f $index)
    $synth.SetOutputToWaveFile($tempWave, $format)
    $synth.Speak((Convert-ToSpeechText $item.text))
    $synth.SetOutputToNull()

    $waveData = Get-WaveData $tempWave
    $start = $audioStream.Length / $bytesPerSecond
    $audioStream.Write($waveData, 0, $waveData.Length)
    $end = $audioStream.Length / $bytesPerSecond
    $timedSegments.Add([ordered]@{
      start = [Math]::Round($start, 3)
      end = [Math]::Round($end, 3)
      text = $item.text
    })

    $pauseSeconds = if ($item.heading) { 0.65 } else { 0.28 }
    $silenceLength = [int]($pauseSeconds * $bytesPerSecond)
    $silenceLength -= $silenceLength % 2
    $silence = [byte[]]::new($silenceLength)
    $audioStream.Write($silence, 0, $silence.Length)

    Remove-Item -LiteralPath $tempWave -Force
    Write-Progress -Activity "Generating SCIM learning audio" `
      -Status ("{0}/{1}: {2}" -f ($index + 1), $displaySegments.Count, $item.text) `
      -PercentComplete ((($index + 1) / $displaySegments.Count) * 100)
  }
} finally {
  $synth.Dispose()
  if (Test-Path -LiteralPath $tempDirectory) {
    Remove-Item -LiteralPath $tempDirectory -Recurse -Force
  }
}

$audioBytes = $audioStream.ToArray()
$audioStream.Dispose()
Write-PcmWave -Path $AudioOutput -Data $audioBytes -SampleRate $sampleRate `
  -Channels $channels -BitsPerSample $bitsPerSample

$vocabularyMeanings = [ordered]@{
  "reflections" = "反思；回顾与感想"
  "friction" = "阻力；造成不顺畅的因素"
  "accountability" = "责任担当；问责"
  "resolution" = "解决；问题处理结果"
  "expertise" = "专业知识与技能"
  "operational" = "运营的；操作层面的"
  "discipline" = "纪律；规范的执行方式"
  "accelerating" = "加速推进"
  "initiative" = "倡议；专项行动"
  "transform" = "转型；彻底改变"
  "frontlog" = "前端待处理案件积压"
  "backlog" = "积压的工作或案件"
  "inventory" = "存量；库存；清单"
  "handoffs" = "工作或客户转交"
  "continuity" = "连续性；衔接性"
  "responsiveness" = "响应速度与能力"
  "outcomes" = "结果；成效"
  "productivity" = "生产力；工作效率"
  "trajectory" = "发展轨迹；趋势"
  "sustainable" = "可持续的"
  "onboarding" = "入职、接入或上线准备"
  "cross-skilling" = "跨技能培养"
  "resilience" = "韧性；恢复能力"
  "adaptable" = "适应性强的"
  "autonomous" = "自主运行的"
  "contextual" = "与上下文相关的"
  "workflow" = "工作流"
  "diagnosis" = "诊断；问题定位"
  "mission-critical" = "对关键任务至关重要的"
  "augmented" = "被增强的；由 AI 辅助的"
  "differentiator" = "差异化优势"
  "evolution" = "演进；逐步发展"
  "elevating" = "提升；提高层次"
  "embedded" = "嵌入的；融入流程的"
  "lifecycle" = "生命周期"
  "stabilizing" = "使稳定；稳固基础"
  "adoption" = "采用；采纳"
  "benchmark" = "标杆；基准"
  "customer-obsessed" = "高度以客户为中心的"
  "relentless" = "坚持不懈的"
  "rigor" = "严谨性；严格标准"
  "accomplished" = "完成；取得成就"
  "ai-native" = "AI 原生的"
}

$vocabulary = [ordered]@{}
foreach ($entry in $vocabularyMeanings.GetEnumerator()) {
  $vocabulary[$entry.Key] = [ordered]@{
    meaning = $entry.Value
    phonetic = Get-Phonetic $entry.Key
  }
}

$duration = [Math]::Round($audioBytes.Length / $bytesPerSecond, 3)
$track = [ordered]@{
  id = "scim-first-60-days"
  title = "SCIM: First 60 Days and the Road Ahead"
  subtitle = "Leadership reflection on operations, people, and AI-first support"
  sourceTitle = "User-provided SCIM leadership update"
  license = "User-provided text for authorized learning use. Confirm publication rights before public deployment."
  audio = "audio/scim-first-60-days-zira.wav"
  duration = $duration
  vocab = $vocabulary
  segments = $timedSegments
}

$json = $track | ConvertTo-Json -Depth 8
$javascript = @"
window.SCIM_60_DAYS_TRACK = $json;
window.AI_LEARNING_TRACKS = window.AI_LEARNING_TRACKS || [];
window.AI_LEARNING_TRACKS.unshift(window.SCIM_60_DAYS_TRACK);
"@

$trackDirectory = Split-Path -Parent $TrackOutput
[System.IO.Directory]::CreateDirectory($trackDirectory) | Out-Null
[System.IO.File]::WriteAllText($TrackOutput, $javascript, [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
  Voice = $VoiceName
  Segments = $timedSegments.Count
  DurationSeconds = $duration
  AudioBytes = $audioBytes.Length
  AudioOutput = $AudioOutput
  TrackOutput = $TrackOutput
  VocabularyCount = $vocabulary.Count
}
