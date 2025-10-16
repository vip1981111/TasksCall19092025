#!/usr/bin/env bash
set -euo pipefail

# === الإعدادات ===
DEFAULT_MSG="WIP: حفظ التعديلات قبل الدمج إلى main"
DELETE_FEATURE_AFTER=false

# قراءة باراميترات
COMMIT_MSG="${1:-$DEFAULT_MSG}"
if [[ "${2:-}" == "-d" ]]; then DELETE_FEATURE_AFTER=true; fi

# تأكد أننا داخل مستودع git
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "❌ لست داخل مجلد مشروع Git"; exit 1; }

# تحديد الفرع الحالي
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$CURRENT_BRANCH" == "main" ]]; then
  echo "⚠️ أنت على main الآن. يُفضّل تشغيل السكربت من فرع الميزة (feature/*)."
  read -p "متابعة على أي حال؟ (y/N): " ans
  [[ "$ans" == "y" || "$ans" == "Y" ]] || exit 1
fi

echo "📌 الفرع الحالي: $CURRENT_BRANCH"

# 0) نسخة أمان (rescue)
BACKUP_BRANCH="rescue/backup-$(date +%Y-%m-%d-%H%M)"
echo "🛟 إنشاء نسخة أمان: $BACKUP_BRANCH"
git checkout -b "$BACKUP_BRANCH" >/dev/null
git checkout "$CURRENT_BRANCH" >/dev/null

# (اختياري) معالجة تحذير upstream المحذوف
set +e
git branch --unset-upstream >/dev/null 2>&1
set -e

# 1) حفظ أي تعديلات حالية
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "💾 حفظ تعديلاتك: $COMMIT_MSG"
  git add -A
  git commit -m "$COMMIT_MSG"
else
  echo "ℹ️ لا توجد تعديلات لحفظها."
fi

# 2) الانتقال إلى main (إن لم يوجد أنشئه)
echo "🔀 الانتقال إلى main"
if git show-ref --verify --quiet refs/heads/main; then
  git checkout main >/dev/null
else
  git checkout -b main >/dev/null
fi

# 3) جلب آخر نسخة من origin/main (إن وُجد remote)
set +e
git pull --rebase origin main >/dev/null 2>&1
set -e

# 4) الدمج من فرع العمل إلى main
if [[ "$CURRENT_BRANCH" != "main" ]]; then
  echo "🔗 دمج $CURRENT_BRANCH -> main"
  git merge --no-ff "$CURRENT_BRANCH" -m "Merge $CURRENT_BRANCH into main"
else
  echo "ℹ️ لا يوجد فرع ميزة مختلف عن main للدمج."
fi

# 5) رفع main إلى GitHub (مع تعيين upstream عند الحاجة)
echo "⤴️ رفع main إلى GitHub"
set +e
git push -u origin main
PUSH_STATUS=$?
set -e
if [[ $PUSH_STATUS -ne 0 ]]; then
  echo "❌ فشل الرفع. تأكد من أن remote 'origin' مضبوط: git remote -v"
  exit 1
fi

# 6) حذف فرع الميزة محليًا (اختياري بعلم -d)
if $DELETE_FEATURE_AFTER && [[ "$CURRENT_BRANCH" != "main" ]]; then
  echo "🧹 حذف فرع الميزة محليًا: $CURRENT_BRANCH"
  git branch -d "$CURRENT_BRANCH" || true
fi

echo "✅ تمت العملية بنجاح."
echo "   آخر سجل:"
git log --oneline -3


