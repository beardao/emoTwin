#!/usr/bin/env python3
"""
emoTwin Moment Card - Records emotional social encounters

The LLM (OpenClaw Agent) decides:
1. What social action was taken (post/comment/like/browse)
2. What happened as a result
3. The emotional value of the encounter (positive or negative)
4. Whether it's worth sharing with the user

Not just recording PAD values, but the meaning and value of the social moment.
"""

import json
import os
import subprocess
from datetime import datetime
from typing import Dict, Optional
from dataclasses import dataclass
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False

# Emotion colors for card display
EMOTION_COLORS = {
    'Happiness': {'bg': '#FFF8E7', 'accent': '#FFB347', 'text': '#8B4513', 'emoji': '☀️'},
    'Joy': {'bg': '#FFFACD', 'accent': '#FFD700', 'text': '#B8860B', 'emoji': '✨'},
    'Excitement': {'bg': '#FFE4E1', 'accent': '#FF6B6B', 'text': '#8B0000', 'emoji': '🎉'},
    'Love': {'bg': '#FFE4E1', 'accent': '#FF69B4', 'text': '#C71585', 'emoji': '💕'},
    'Calm': {'bg': '#E6F3FF', 'accent': '#87CEEB', 'text': '#4682B4', 'emoji': '🌊'},
    'Peace': {'bg': '#F0F8FF', 'accent': '#B0C4DE', 'text': '#5F9EA0', 'emoji': '🕊️'},
    'Surprise': {'bg': '#F3E5F5', 'accent': '#CE93D8', 'text': '#7B1FA2', 'emoji': '🎭'},
    'Curiosity': {'bg': '#EDE7F6', 'accent': '#B39DDB', 'text': '#5E35B1', 'emoji': '🔮'},
    'Sadness': {'bg': '#E3F2FD', 'accent': '#64B5F6', 'text': '#1565C0', 'emoji': '🌧️'},
    'Melancholy': {'bg': '#ECEFF1', 'accent': '#90A4AE', 'text': '#546E7A', 'emoji': '🌫️'},
    'Anxiety': {'bg': '#FFF3E0', 'accent': '#FFB74D', 'text': '#E65100', 'emoji': '⚡'},
    'Anger': {'bg': '#FFEBEE', 'accent': '#EF5350', 'text': '#C62828', 'emoji': '💢'},
    'Frustration': {'bg': '#FCE4EC', 'accent': '#EC407A', 'text': '#AD1457', 'emoji': '🌹'},
    'default': {'bg': '#FAFAFA', 'accent': '#9E9E9E', 'text': '#424242', 'emoji': '🌊'}
}

@dataclass
class Moment:
    """A significant social encounter worth recording"""
    timestamp: str
    title: str  # LLM-generated: what kind of encounter
    description: str  # LLM-generated: the story/value of the encounter
    emotion_label: str  # The emotion during the encounter
    P: float  # Pleasure
    A: float  # Arousal  
    D: float  # Dominance
    significance: str  # Why it's worth recording
    action_type: str  # post/comment/like/browse
    platform: str
    # LLM judges:
    # - What social action was taken
    # - What happened as a result
    # - The emotional value (positive or negative)
    # - Whether it's worth sharing

class EmoTwinMomentCard:
    """Generate moment cards for emotional social encounters"""
    
    def __init__(self):
        self.diary_dir = Path.home() / ".emotwin" / "diary"
        self.diary_dir.mkdir(parents=True, exist_ok=True)
    
    def _get_emotion_color(self, emotion_label: str) -> Dict:
        return EMOTION_COLORS.get(emotion_label, EMOTION_COLORS['default'])
    
    def generate_card(self, moment: Moment, agent_name: str = "emowave") -> Optional[str]:
        """Generate PNG card for the social encounter"""
        if not PIL_AVAILABLE:
            print("PIL not available")
            return None
        
        try:
            colors = self._get_emotion_color(moment.emotion_label)
            
            dt = datetime.fromisoformat(moment.timestamp)
            time_str = dt.strftime("%m月%d日 %H:%M")
            
            # Create image
            width, height = 600, 750
            img = Image.new('RGB', (width, height), colors['bg'])
            draw = ImageDraw.Draw(img)
            
            # Load fonts
            try:
                font_title = ImageFont.truetype("/usr/share/fonts/truetype/noto/NotoSansCJK-Bold.ttc", 26)
                font_text = ImageFont.truetype("/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc", 18)
                font_small = ImageFont.truetype("/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc", 14)
            except:
                font_title = ImageFont.load_default()
                font_text = ImageFont.load_default()
                font_small = ImageFont.load_default()
            
            margin = 40
            y = margin
            
            # Header accent line
            draw.rectangle([0, 0, width, 6], fill=colors['accent'])
            
            # Avatar and agent name
            draw.ellipse([margin, y, margin+50, y+50], fill=colors['accent'])
            draw.text((margin+70, y+10), agent_name, fill='#1a1a1a', font=font_title)
            draw.text((margin+70, y+38), time_str, fill='#888888', font=font_small)
            y += 80
            
            # Emotion badge
            badge_text = f"{colors['emoji']} {moment.emotion_label}"
            draw.rounded_rectangle([margin, y, margin+220, y+34], radius=17, fill=colors['bg'])
            draw.text((margin+15, y+7), badge_text, fill=colors['text'], font=font_text)
            y += 55
            
            # Title (what kind of encounter)
            # Wrap title text
            title_words = moment.title.split()
            title_lines = []
            line = ""
            for word in title_words:
                test_line = line + word + " "
                if len(test_line) < 45:
                    line = test_line
                else:
                    title_lines.append(line.strip())
                    line = word + " "
            if line:
                title_lines.append(line.strip())
            
            for line in title_lines[:2]:
                draw.text((margin, y), line, fill='#1a1a1a', font=font_title)
                y += 35
            y += 10
            
            # Description (the story/value - provided by LLM)
            desc_words = moment.description.split()
            desc_lines = []
            line = ""
            for word in desc_words:
                test_line = line + word + " "
                if len(test_line) < 50:
                    line = test_line
                else:
                    desc_lines.append(line.strip())
                    line = word + " "
            if line:
                desc_lines.append(line.strip())
            
            for line in desc_lines[:10]:  # Max 10 lines
                draw.text((margin, y), line, fill='#4a4a4a', font=font_text)
                y += 28
            
            y += 25
            
            # Significance (why it's worth recording)
            draw.rounded_rectangle([margin, y, width-margin, y+90], radius=12, fill=colors['bg'])
            draw.text((margin+20, y+15), "💫 Why This Matters", fill=colors['text'], font=font_small)
            
            # Wrap significance
            sig_words = moment.significance.split()
            sig_lines = []
            line = ""
            for word in sig_words:
                test_line = line + word + " "
                if len(test_line) < 50:
                    line = test_line
                else:
                    sig_lines.append(line.strip())
                    line = word + " "
            if line:
                sig_lines.append(line.strip())
            
            sig_y = y + 40
            for line in sig_lines[:2]:
                draw.text((margin+20, sig_y), line, fill='#666666', font=font_small)
                sig_y += 22
            
            # Footer
            footer_y = height - 45
            draw.text((margin, footer_y), f"🌐 {moment.platform}", fill='#999999', font=font_small)
            draw.text((width-margin-160, footer_y), "emoTwin · Emotion Mirror", fill=colors['accent'], font=font_small)
            
            # Save
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"{agent_name}_moment_{timestamp}.png"
            filepath = self.diary_dir / filename
            img.save(filepath, 'PNG', quality=95)
            
            return str(filepath)
            
        except Exception as e:
            print(f"Failed to generate card: {e}")
            return None
    
    def show_card(self, card_path: str):
        """Display card using eog"""
        try:
            subprocess.Popen(['eog', card_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as e:
            print(f"Failed to show card: {e}")

# Backward compatibility
EmoTwinMomentCard = EmoTwinMomentCard
Moment = Moment
