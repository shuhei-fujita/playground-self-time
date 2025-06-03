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
# Check if KINTAI_LOG_FILE is set, otherwise use default
if [ -n "$KINTAI_LOG_FILE" ]; then
  LOG_FILE="$KINTAI_LOG_FILE"
else
  LOG_FILE="$HOME/git/samples/playground-self-time/log.txt"
fi
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

  # 本日の総勤務時間を計算するため、ログを一行ずつ処理
  # IN と OUT のペアを見つけて、その間の時間を秒単位で加算していく
  total_sec=0
  in_time="" # 直近のIN時刻を保持。OUTが見つかったらこれでペアにする
  # today_logs (本日分のログ) を1行ずつ読み込む
  while read -r line; do
    t_date=$(echo "$line" | awk '{print $1}')
    t_time=$(echo "$line" | awk '{print $2}')
    t_type=$(echo "$line" | awk '{print $3}')
    if [ "$t_type" = "IN" ]; then
      # IN時刻を記録
      in_time="$t_date $t_time"
    elif [ "$t_type" = "OUT" ] && [ -n "$in_time" ]; then
      # OUT時刻があり、かつ直前にIN時刻が記録されていればペア成立
      out_time="$t_date $t_time"
      sec_in=$(to_unixtime "$in_time")
      sec_out=$(to_unixtime "$out_time")
      # OUT時刻がIN時刻以降であることを確認（ありえないが念のため）
      if [ $sec_out -ge $sec_in ]; then
        total_sec=$((total_sec + sec_out - sec_in)) # 勤務時間を加算
      fi
      in_time="" # IN時刻をリセットして次のペアを探す
    fi
  done <<< "$today_logs"

  # 本日のログ処理後、最後の打刻がINのまま（まだ退勤していない）場合
  # そのIN時刻から現在時刻までの時間を勤務時間に加算する
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

  # --- 現在の出退勤ステータスを判断するためのロジック ---
  # ログファイル全体から、最も最後の "IN" の記録を探す
  # これにより、日をまたいで作業している場合や、過去の打刻忘れ修正後の正しいステータスを判定する
  last_in_line=$(grep -n "IN" "$LOG_FILE" | tail -n1 | cut -d: -f1)
  last_in_raw=$(sed -n "${last_in_line}p" "$LOG_FILE") # 行番号を使ってその行の内容を取得
  last_in_date=$(echo "$last_in_raw" | awk '{print $1}')
  last_in_time=$(echo "$last_in_raw" | awk '{print $2}')

  # 見つかった最後のIN記録よりも後の行で、最初の "OUT" の記録を探す
  # last_in_line が空（INが一度もない）場合は "+" から始まるのでエラーになるため、last_in_lineが存在するか確認
  if [ -n "$last_in_line" ]; then
    last_out_line_rel=$(tail -n +$((last_in_line+1)) "$LOG_FILE" | grep -n "OUT" | head -n1 | cut -d: -f1)
  else
    last_out_line_rel=""
  fi
  # last_out_line_rel が見つかった場合（つまり、最後のINの後にOUTがある場合）
  if [ -n "$last_out_line_rel" ]; then
    # last_out_line_rel は last_in_line より後の相対的な行番号なので、絶対行番号に変換
    last_out_line=$((last_in_line + last_out_line_rel))
    last_out_raw=$(sed -n "${last_out_line}p" "$LOG_FILE")
    last_out_date=$(echo "$last_out_raw" | awk '{print $1}')
    last_out_time=$(echo "$last_out_raw" | awk '{print $2}')
  else
    last_out_date=""
    last_out_time=""
  fi

  # 最終的な出退勤ステータスを判定・表示
  # 条件1: 最後のIN記録があり (`last_in_time`が空でない)
  # 条件2: AND (
  #   最後のINに対応するOUT記録がまだない (`last_out_time`が空)
  #   OR 最後のOUT記録が最後のIN記録よりも古い (これは通常、手動編集や過去ログの場合にありえる)
  # )
  # 上記が満たされれば「出勤中」。
  if [ -n "$last_in_time" ] && { [ -z "$last_out_time" ] || [ "$last_out_date $last_out_time" \< "$last_in_date $last_in_time" ]; }; then
    echo "🟢 現在の状態: 出勤中"
  # 条件1: 最後のIN記録があり
  # 条件2: AND 最後のOUT記録もある (そして上記「出勤中」の条件に当てはまらない)
  # この場合、「退勤中」。
  elif [ -n "$last_in_time" ] && [ -n "$last_out_time" ]; then
    echo "🔵 現在の状態: 退勤中"
  # どちらでもない場合（例: ログが空、IN記録がないなど）
  else
    echo "⏱ 勤務時間: -" # 勤務時間も不明瞭なのでハイフン表示
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
  in) clock_in ;;
  out) clock_out ;;
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
    echo "使い方: kintai [in|out|log|status]"
    echo "  in: 出勤打刻"
    echo "  out: 退勤打刻"
    echo "  log: ログ表示"
    echo "  status: 状況表示"
    echo "引数なし: 自動で出勤/退勤を切り替え"
    ;;
esac
