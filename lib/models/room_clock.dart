String remainingLabel(DateTime? expiresAt, DateTime now) {
  if (expiresAt == null) return '참여자 입장 후 24시간';
  final left = expiresAt.difference(now);
  if (left <= Duration.zero) return '만료됨 · 발표자만 입장';
  if (left >= const Duration(hours: 1)) return '남은 시간 ${left.inHours}시간';
  final minutes = left.inMinutes < 1 ? 1 : left.inMinutes;
  return '남은 시간 $minutes분';
}
