#!/bin/bash

to_unixtime() {
  # GNU date優先、なければBSD date
  if date -d "1970-01-01" +%s >/dev/null 2>&1; then
    date -d "$1" +%s
  else
    date -j -f "%Y-%m-%d %H:%M:%S" "$1" +%s
  fi
}

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

  today=$(date +%Y-%m-%d)
  # 本日分のログを抽出
  today_logs=$(grep "^$today" "$LOG_FILE")

  # IN/OUTペアごとに合計勤務時間を計算
  total_sec=0
  in_time=""
  while read -r line; do
    t_date=$(echo "$line" | awk '{print $1}')
    t_time=$(echo "$line" | awk '{print $2}')
    t_type=$(echo "$line" | awk '{print $3}')
    if [ "$t_type" = "IN" ]; then
      in_time="$t_date $t_time"
    elif [ "$t_type" = "OUT" ] && [ -n "$in_time" ]; then
      out_time="$t_date $t_time"
      sec_in=$(to_unixtime "$in_time")
      sec_out=$(to_unixtime "$out_time")
      if [ $sec_out -ge $sec_in ]; then
        total_sec=$((total_sec + sec_out - sec_in))
      fi
      in_time=""
    fi
  done <<< "$today_logs"

  # 最後がINでOUTがなければ現在時刻まで加算
  if [ -n "$in_time" ]; then
    sec_in=$(to_unixtime "$in_time")
    now=$(date +%s)
    if [ $now -ge $sec_in ]; then
      total_sec=$((total_sec + now - sec_in))
    fi
  fi

  hours=$((total_sec / 3600))
  mins=$(((total_sec % 3600) / 60))
  secs=$((total_sec % 60))
  echo "⏱ 本日の勤務時間: ${hours}時間${mins}分${secs}秒"

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
  elif [ -n "$last_in_time" ] && [ -n "$last_out_time" ]; then
    echo "🔵 現在の状態: 退勤中"
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
