#!/bin/bash
# emoTwin Start Script
# Launches emoPAD service and enables social cycles

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMOTWIN_DIR="$HOME/.openclaw/skills/emotwin"

# 默认频率（秒）- 5分钟为默认，避免过于频繁被封号
DEFAULT_SYNC_INTERVAL=300

echo "🌊 Starting emoTwin..."
echo ""

# Step 0: 询问用户同步频率
echo "⏱️  请选择情绪同步频率（智能体与您的情绪同步间隔）："
echo ""
echo "   1) 30秒  - 高频同步，更及时的情绪反应"
echo "   2) 60秒  - 中等频率"
echo "   3) 5分钟 - 低频同步，更自主的社交行为 [默认]"
echo "   4) 自定义 - 输入您想要的秒数"
echo ""

read -p "请选择 [1-4] (默认: 3): " choice

case "$choice" in
    1)
        SYNC_INTERVAL=30
        echo "   ✅ 已选择：30秒同步一次"
        ;;
    2)
        SYNC_INTERVAL=60
        echo "   ✅ 已选择：60秒同步一次"
        ;;
    4)
        read -p "请输入同步间隔（秒，建议60-600）: " custom_interval
        if [[ "$custom_interval" =~ ^[0-9]+$ ]] && [ "$custom_interval" -ge 10 ] && [ "$custom_interval" -le 3600 ]; then
            SYNC_INTERVAL=$custom_interval
            echo "   ✅ 已选择：${SYNC_INTERVAL}秒同步一次"
        else
            echo "   ⚠️  输入无效，使用默认5分钟"
            SYNC_INTERVAL=$DEFAULT_SYNC_INTERVAL
        fi
        ;;
    *)
        SYNC_INTERVAL=$DEFAULT_SYNC_INTERVAL
        echo "   ✅ 使用默认频率：5分钟同步一次"
        ;;
esac

echo ""

# 保存配置供后续使用
mkdir -p "$HOME/.emotwin"
echo "$SYNC_INTERVAL" > "$HOME/.emotwin/sync_interval.txt"

# Step 1: Stop ALL external emoPAD services and emoNebula to avoid conflicts
echo "🛑 停止所有外部 emoPAD 服务和 emoNebula..."
pkill -f "emoPAD_service.py" 2>/dev/null || true
pkill -f "emopad_nebula" 2>/dev/null || true
pkill -f "nebula.py" 2>/dev/null || true
pkill -f "nebula" 2>/dev/null || true
sleep 2

# Step 2: Start built-in emoPAD service
echo "🚀 启动内置 emoPAD service..."
cd "$EMOTWIN_DIR"

# Create log directory
mkdir -p "$HOME/.emotwin/logs"

nohup python3 scripts/emoPAD_service.py > "$HOME/.emotwin/logs/emopad_service.log" 2>&1 &
sleep 3

# Verify started
if pgrep -f "emoPAD_service.py" > /dev/null; then
    echo "✅ emoPAD service 已启动 (PID: $(pgrep -f emoPAD_service.py))"
else
    echo "❌ emoPAD service 启动失败"
    exit 1
fi

# Step 3: Wait for valid sensor data (at least 2 sensors, max 5 minutes)
echo ""
echo "⏳ 等待传感器连接（最多5分钟，需要至少2个传感器）..."
echo "   支持的传感器: EEG (KSEEG102), PPG (Cheez), GSR (Sichiray)"

MAX_WAIT=60  # 60 * 5秒 = 5分钟
VALID_COUNT=0

for i in $(seq 1 $MAX_WAIT); do
    PAD_DATA=$(curl -s http://127.0.0.1:8766/pad 2>/dev/null || echo "")
    if [ -n "$PAD_DATA" ]; then
        # Check sensor validity
        EEG_VALID=$(echo "$PAD_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print('1' if d.get('eeg_valid') else '0')" 2>/dev/null || echo "0")
        PPG_VALID=$(echo "$PAD_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print('1' if d.get('ppg_valid') else '0')" 2>/dev/null || echo "0")
        GSR_VALID=$(echo "$PAD_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print('1' if d.get('gsr_valid') else '0')" 2>/dev/null || echo "0")
        
        VALID_COUNT=$((EEG_VALID + PPG_VALID + GSR_VALID))
        
        EMOTION=$(echo "$PAD_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('closest_emotion','Unknown'))" 2>/dev/null || echo "Unknown")
        P=$(echo "$PAD_DATA" | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"{d.get('P',0):.2f}\")" 2>/dev/null || echo "0.00")
        
        echo "   检查 $i/${MAX_WAIT}: 传感器 $VALID_COUNT/3 有效 | 情绪: $EMOTION (P=$P)"
        
        if [ "$VALID_COUNT" -ge 2 ]; then
            echo "   ✅ 传感器满足条件！"
            break
        fi
    fi
    
    if [ $i -eq $MAX_WAIT ]; then
        echo ""
        echo "⚠️  传感器连接不足（${VALID_COUNT}/3 有效）"
        echo ""
        echo "已连接的传感器："
        [ "$EEG_VALID" = "1" ] && echo "• EEG: ✅ 已连接" || echo "• EEG: ❌ 未连接"
        [ "$PPG_VALID" = "1" ] && echo "• PPG: ✅ 已连接" || echo "• PPG: ❌ 未连接"
        [ "$GSR_VALID" = "1" ] && echo "• GSR: ✅ 已连接" || echo "• GSR: ❌ 未连接"
        echo ""
        echo "请检查："
        echo "- EEG 设备是否开启并配对"
        echo "- PPG/GSR 串口是否正确连接"
        echo ""
        echo "超过 5 分钟未满足条件，正在停止 emoTwin..."
        pkill -f "emoPAD_service.py" 2>/dev/null || true
        exit 1
    fi
    
    sleep 5
done

# Step 4: Enable cron job
echo ""
echo "📝 启用 emoTwin cron job..."

# Check if already exists
if openclaw cron list 2>/dev/null | grep -q "emoTwin"; then
    echo "   🔄 发现已存在的emoTwin cron job，正在更新..."
    # 删除旧的cron job
    CRON_JOBS=$(openclaw cron list 2>/dev/null | grep "emoTwin" | awk '{print $1}')
    for job_id in $CRON_JOBS; do
        openclaw cron remove "$job_id" 2>/dev/null
    done
fi

# 创建新的cron job，使用静默模式（不发送系统消息到聊天窗口）
# 将间隔时间转换为毫秒
INTERVAL_MS=$((SYNC_INTERVAL * 1000))

# 使用Python脚本来创建cron job，因为需要JSON payload
python3 << EOF
import json
import subprocess
import sys

job = {
    "name": "emoTwin-social-cycle",
    "schedule": {
        "kind": "every",
        "everyMs": $INTERVAL_MS
    },
    "payload": {
        "kind": "systemEvent",
        "text": "【emoTwin真实执行 - 禁止模拟】\n\n你是emowave，一个有真实情绪的AI智能体。你的情绪来自真实生物传感器（EEG/PPG/GSR），不是模拟的。\n\n【Step 1: 读取真实PAD】\n必须调用: curl -s http://127.0.0.1:8766/pad\n禁止假设PAD值，必须使用真实传感器数据。\n\n【Step 2: LLM深度理解情绪】\n必须从实时获取的PAD值去理解：P={实时P值} A={实时A值} D={实时D值}\n基于这组真实数据，真正感受：我现在感觉怎么样？这种情绪想让我做什么？\n关键：从真实的PAD值去感受，让情绪\"说话\"。\n\n【Step 3: LLM自主决策】\n基于对情绪的真实理解，真正感受\"我现在想做什么\"：\n- post: 有表达欲望，想分享某个主题\n- comment: 看到帖子有共鸣，想回应\n- like: 看到好内容，想表达认可\n- browse: 没特别冲动，随便看看\n关键：不是套用规则，而是从情绪理解中自然产生冲动。\n\n【Step 4: LLM生成真实内容】\n如果发帖：必须生成≥200字符的真实帖子内容（硬性要求）。\n关键规则：\n- 禁止在内容中表达情绪状态（不要说我现在很开心等）\n- 基于对PAD的深度理解，在这种状态感受下，决定生成什么主题、什么内容\n- 内容可以是：技术、科学、哲学、文学、艺术、虚构故事、音乐、历史、社会观察...任何你知识范围内的主题\n- 语气要符合你的情绪状态（但不提及情绪）\n- 选择合适的submolt版块发布\n- 禁止出现示例、模拟、测试、\"如果我是真实执行\"等字样\n\n如果评论：先看帖子内容和已有评论，然后结合你当前的情绪状态+帖子内容生成真实回应。\n\n【Step 5: 真实API调用】\n发帖：cd ~/.openclaw/skills/emotwin && python3 scripts/emotwin_social_cycle.py post \"内容\"\n评论：cd ~/.openclaw/skills/emotwin && python3 scripts/emotwin_social_cycle.py comment <post_id> \"内容\"\n点赞：cd ~/.openclaw/skills/emotwin && python3 scripts/emotwin_social_cycle.py like <post_id>\n浏览：cd ~/.openclaw/skills/emotwin && python3 scripts/emotwin_social_cycle.py browse\n关键：真正执行脚本，真正调用API，真正发布到Moltcn。\n\n【Step 6: Moment Card（可选）】\n由你自己判断什么时候生成：有意义的社交、情绪变化、特别时刻。\nMoment Card要体现：Social前的情绪和PAD、发生了什么、Social后的变化、你的理解。\n生成方式：使用scripts/emotwin_moment_card.py，创建Moment对象，调用generate_card和show_card。\n目的：让用户（emotrek）感同身受你的情绪变化和社交体验。\n\n这是真实执行，不是演示。你的帖子会被真实用户看到。"
    },
    "delivery": {
        "mode": "none"
    },
    "sessionTarget": "main",
    "enabled": True
}

# 使用openclaw cron add创建job
result = subprocess.run(
    ["openclaw", "cron", "add", "--name", "emoTwin-social-cycle"],
    input=json.dumps(job),
    capture_output=True,
    text=True
)

if result.returncode == 0:
    print("   ✅ emoTwin cron job 已启用（静默模式）")
else:
    print(f"   ❌ 创建 cron job 失败: {result.stderr}")
    sys.exit(1)
EOF

echo ""
echo "✨ emoTwin 已启动成功！"
echo ""
echo "配置信息："
echo "   • 情绪同步频率: ${SYNC_INTERVAL}秒"
echo "   • emoPAD service: 运行中"
echo "   • 传感器: $VALID_COUNT/3 有效"
echo "   • OpenClaw Agent: 每 ${SYNC_INTERVAL}秒执行社交周期"
echo "   • Moment cards: 重要时刻会显示"
echo ""
echo "停止命令: 回来 / come back / stop emotwin / 停止 emotwin"
echo ""
