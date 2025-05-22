#!/bin/bash

SCRIPT_DIR="$(dirname "$(cd "$(dirname "$0")"; pwd)/$(basename "$0")")"
LOG_FILE="$HOME/git/samples/playground-self-time/log.txt"
TODAY=$(date +%Y-%m-%d)

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

cmd="$1"

clock_in() {
  echo "$TODAY $(date +%H:%M:%S) IN" >> "$LOG_FILE"
  echo "✅ 出勤打刻しました：$(date +%H:%M:%S)"
}

clock_out() {
  echo "$TODAY $(date +%H:%M:%S) OUT" >> "$LOG_FILE"
  echo "✅ 退勤打刻しました：$(date +%H:%M:%S)"
}

status() {
  echo "📅 日付: $(date '+%Y-%m-%d（%a）')"
  echo "===="

  # ログ全体から最後のIN行番号を取得
  last_in_line=$(grep -n "IN" "$LOG_FILE" | tail -n1 | cut -d: -f1)
  last_in_raw=$(sed -n "${last_in_line}p" "$LOG_FILE")
  last_in_date=$(echo "$last_in_raw" | awk '{print $1}')
  last_in_time=$(echo "$last_in_raw" | awk '{print $2}')

  # そのIN以降で最初のOUT行番号を取得
  last_out_line_rel=$(tail -n +$((last_in_line+1)) "$LOG_FILE" | grep -n "OUT" | head -n1 | cut -d: -f1)
  if [ -n "$last_out_line_rel" ]; then
    last_out_line=$((last_in_line + last_out_line_rel))
    last_out_raw=$(sed -n "${last_out_line}p" "$LOG_FILE")
    last_out_date=$(echo "$last_out_raw" | awk '{print $1}')
    last_out_time=$(echo "$last_out_raw" | awk '{print $2}')
  else
    last_out_date=""
    last_out_time=""
  fi

  # ステータス表示
  if [ -n "$last_in_time" ] && { [ -z "$last_out_time" ] || [ "$last_out_date $last_out_time" \< "$last_in_date $last_in_time" ]; }; then
    echo "🟢 現在の状態: 出勤中"
    # 出勤中（退勤がまだ）
    now=$(date +%s)
    sec_in=$(date -j -f "%Y-%m-%d %H:%M:%S" "$last_in_date $last_in_time" +%s)
    diff_sec=$((now - sec_in))
    hours=$((diff_sec / 3600))
    mins=$(((diff_sec % 3600) / 60))
    secs=$((diff_sec % 60))
    echo "⏱ 出勤中: ${hours}時間${mins}分${secs}秒経過"
  elif [ -n "$last_in_time" ] && [ -n "$last_out_time" ]; then
    echo "🔵 現在の状態: 退勤中"
    sec_in=$(date -j -f "%Y-%m-%d %H:%M:%S" "$last_in_date $last_in_time" +%s)
    sec_out=$(date -j -f "%Y-%m-%d %H:%M:%S" "$last_out_date $last_out_time" +%s)
    if [ $sec_out -ge $sec_in ]; then
      diff_sec=$((sec_out - sec_in))
      hours=$((diff_sec / 3600))
      mins=$(((diff_sec % 3600) / 60))
      secs=$((diff_sec % 60))
      echo "⏱ 最終勤務時間: ${hours}時間${mins}分${secs}秒"
    else
      echo "⚠️ 退勤が出勤より前です"
    fi
  else
    echo "⏱ 勤務時間: -"
  fi

  # 打刻状況の表示
  if [ -n "$last_in_time" ]; then echo "🕘 最終出勤: $last_in_date $last_in_time"; else echo "🕘 出勤: 未打刻"; fi
  if [ -n "$last_out_time" ]; then echo "🕕 最終退勤: $last_out_date $last_out_time"; else echo "🕕 退勤: 未打刻"; fi
}

log_show() {
  echo "📂 ログファイル: $LOG_FILE"
  cat "$LOG_FILE"
}

case "$cmd" in
  log) log_show ;;
  status) status ;;
  "" )
    # 引数なしは自動切り替え
    today=$(date +%Y-%m-%d)
    last=$(grep "^$today" "$LOG_FILE" | tail -n1 | awk '{print $3}')
    if [ "$last" = "IN" ]; then
      clock_out
    else
      clock_in
    fi
    ;;
  *)
    echo "使い方: kintai [log|status]"
    echo "引数なしで自動 in/out 打刻"
    ;;
esac
