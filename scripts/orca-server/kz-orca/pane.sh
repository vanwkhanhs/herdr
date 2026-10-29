# Khoi dong mot pane Orca tren server: builder | reviewer | debug.
#
# Dung bang '. pane.sh <role>' (SOURCE, khong chay con): Orca go lenh nay vao bash cua
# pane, source thi ham 'ngu' va bien moi truong con lai trong shell sau khi claude thoat.
# Vi source: KHONG dung 'exit' trong file nay - se giet luon shell cua pane.
#
# Lenh ngan co y: Orca go lai lenh khoi dong khi khoi dong lai, chuoi dai bi cat
# (PITFALLS #2). Moi logic nam o day va trong kz_orca.py.

KZ_HOME="$HOME/.local/opt/kz-orca"
export KZ_ROLE="$1"
export KZ_PROJECT_DIR="$PWD"
# Ten pane: Orca hien title song cua tien trinh (chuoi OSC). Cam Claude ghi de.
export CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1
printf '\033]0;%s\007' "$KZ_ROLE"

python3 "$KZ_HOME/kz_orca.py" register "$KZ_ROLE" "$PWD"

if [ "$KZ_ROLE" = debug ]; then
    # Prompt mac dinh cua Ubuntu ghi lai title moi lan hien prompt -> giu ten 'debug'
    PS1='\u@\h:\w\$ '
    PROMPT_COMMAND='printf "\033]0;debug\007"'
    # Thay nut Sleep cua Orca: dong het terminal cua project bang --all
    ngu() { python3 "$KZ_HOME/kz_orca.py" sleep "$KZ_PROJECT_DIR"; }
    echo "Go 'ngu' de cho project nay ngu."
else
    eval "claude $(python3 "$KZ_HOME/kz_orca.py" claude-args "$KZ_ROLE" "$PWD")"
fi
