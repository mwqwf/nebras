import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../data/chat_repository.dart';
import 'chat_media.dart';

/// ألوان أسماء المرسِلين (مثل واتساب — لون ثابت لكلّ عضو).
const List<Color> _senderColors = [
  Color(0xFF34D399),
  Color(0xFF60A5FA),
  Color(0xFFF472B6),
  Color(0xFFFBBF24),
  Color(0xFFA78BFA),
  Color(0xFFF87171),
  Color(0xFF2DD4BF),
  Color(0xFFFB923C),
];

Color senderColor(String uid) =>
    _senderColors[uid.hashCode.abs() % _senderColors.length];

/// صورة عضو دائريّة (المخصّصة أولاً ثم Google ثم الحرف الأوّل) مع نقطة
/// «متصل الآن» اختياريّة.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    super.key,
    required this.uid,
    required this.name,
    required this.photo,
    this.radius = 16,
    this.showOnline = false,
    this.online = false,
  });

  final String uid;
  final String name;
  final String photo;
  final double radius;
  final bool showOnline;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: senderColor(uid).withValues(alpha: 0.25),
      backgroundImage:
          photo.isNotEmpty ? CachedNetworkImageProvider(photo) : null,
      child: photo.isEmpty
          ? Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                  color: senderColor(uid),
                  fontSize: radius * 0.85,
                  fontWeight: FontWeight.w700),
            )
          : null,
    );
    if (!showOnline) return avatar;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        PositionedDirectional(
          bottom: -1,
          end: -1,
          child: Container(
            width: radius * 0.62,
            height: radius * 0.62,
            decoration: BoxDecoration(
              color: online ? const Color(0xFF22C55E) : NebrasColors.textMuted,
              shape: BoxShape.circle,
              border: Border.all(color: NebrasColors.bg, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}

/// فقاعة رسالة بنمط واتساب: يمين للمرسِل، يسار للبقيّة، مع صورة واسم
/// المرسِل (وسام 👑 للمالك)، معاينة الردّ، المحتوى، التفاعلات، الوقت
/// وعلامات القراءة ✓✓.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.msg,
    required this.showSenderHeader,
    required this.members,
    required this.readByAll,
    required this.onLongPress,
    required this.onReplyTap,
    required this.onReactionsTap,
  });

  final ChatMessage msg;
  final bool showSenderHeader;

  /// خريطة الأعضاء الحاليّة {uid: ChatMember} — للصور الحيّة ووسام المالك.
  final Map<String, ChatMember> members;

  /// هل قرأ الرسالةَ كلُّ الأعضاء الآخرين (✓✓ زرقاء).
  final bool readByAll;

  final void Function(ChatMessage) onLongPress;
  final void Function(ChatReplyRef) onReplyTap;
  final void Function(ChatMessage) onReactionsTap;

  ChatMember? get _sender => members[msg.senderId];

  @override
  Widget build(BuildContext context) {
    // رسائل النظام (الموجز اليومي، جسر الاقتراحات…) — بطاقة وسطيّة مميّزة.
    if (msg.senderId == 'system') return _systemCard(context);

    final mine = msg.isMine;
    final bubbleColor = mine ? const Color(0xFF0B3B2A) : NebrasColors.surface;
    final radius = BorderRadius.only(
      topRight: const Radius.circular(14),
      topLeft: const Radius.circular(14),
      bottomRight: Radius.circular(mine ? 3 : 14),
      bottomLeft: Radius.circular(mine ? 14 : 3),
    );

    final bubble = GestureDetector(
      onLongPress: () => onLongPress(msg),
      child: Container(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: radius,
          border: Border.all(
              color: mine ? const Color(0xFF14532D) : NebrasColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!mine && showSenderHeader) _senderHeader(),
            if (msg.replyTo != null) _replyPreview(context),
            if (msg.deleted) _deletedBody() else _body(context),
            const SizedBox(height: 2),
            _footer(),
          ],
        ),
      ),
    );

    // صورة المرسِل تظهر بجوار أوّل رسالة في كلّ سلسلة (مثل واتساب).
    final withAvatar = mine
        ? bubble
        : Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (showSenderHeader)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: MemberAvatar(
                    uid: msg.senderId,
                    name: _sender?.displayName ?? msg.senderName,
                    photo: _sender?.displayPhoto ?? msg.senderPhoto,
                    radius: 15,
                  ),
                )
              else
                const SizedBox(width: 36),
              Flexible(child: bubble),
            ],
          );

    return Align(
      // في RTL: رسائلي على اليمين (start)، رسائل الآخرين على اليسار (end).
      alignment:
          mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            withAvatar,
            if (msg.reactions.isNotEmpty && !msg.deleted)
              _reactionsBar(context),
          ],
        ),
      ),
    );
  }

  Widget _systemCard(BuildContext context) {
    return Center(
      child: GestureDetector(
        onLongPress: () => onLongPress(msg),
        child: Container(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.86),
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: NebrasColors.sidebarActive,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: NebrasColors.emeraldDark.withValues(alpha: 0.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.auto_awesome,
                      size: 14, color: NebrasColors.emerald),
                  SizedBox(width: 6),
                  Text('نبراس',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: NebrasColors.emerald)),
                ],
              ),
              const SizedBox(height: 6),
              Text(msg.deleted ? 'تم حذف هذه الرسالة' : msg.text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, height: 1.6)),
              const SizedBox(height: 4),
              Text(intl.DateFormat('HH:mm').format(msg.createdAt),
                  style: const TextStyle(
                      fontSize: 9.5, color: NebrasColors.textMuted)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _senderHeader() {
    final isOwner = _sender?.isOwner ?? false;
    final isMod = !isOwner && (_sender?.isChatModerator ?? false);
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              _sender?.displayName ?? msg.senderName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isOwner ? NebrasColors.amber : senderColor(msg.senderId),
              ),
            ),
          ),
          if (isOwner) ...[
            const SizedBox(width: 4),
            const Text('👑', style: TextStyle(fontSize: 11)),
            const SizedBox(width: 2),
            const Text('المالك',
                style: TextStyle(fontSize: 10, color: NebrasColors.amber)),
          ] else if (isMod) ...[
            const SizedBox(width: 4),
            const Text('⭐', style: TextStyle(fontSize: 10)),
            const SizedBox(width: 2),
            const Text('مشرف',
                style: TextStyle(fontSize: 10, color: NebrasColors.emerald)),
          ],
        ],
      ),
    );
  }

  /// شريط التفاعلات أسفل الفقاعة (مجمَّع بالإيموجي مع العدد).
  Widget _reactionsBar(BuildContext context) {
    final counts = <String, int>{};
    for (final e in msg.reactions.values) {
      counts[e] = (counts[e] ?? 0) + 1;
    }
    final myEmoji =
        msg.reactions[FirebaseAuth.instance.currentUser?.uid ?? ''];
    return GestureDetector(
      onTap: () => onReactionsTap(msg),
      child: Container(
        margin: const EdgeInsets.only(top: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: NebrasColors.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: myEmoji != null
                  ? NebrasColors.emeraldDark
                  : NebrasColors.border),
        ),
        child: Text(
          counts.entries
              .map((e) => e.value > 1 ? '${e.key} ${e.value}' : e.key)
              .join('  '),
          style: const TextStyle(fontSize: 12.5),
        ),
      ),
    );
  }

  Widget _replyPreview(BuildContext context) {
    final r = msg.replyTo!;
    return InkWell(
      onTap: () => onReplyTap(r),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(8),
          border: BorderDirectional(
            start: BorderSide(color: senderColor(r.senderId), width: 3),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(r.senderName,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: senderColor(r.senderId))),
            const SizedBox(height: 2),
            Text(
              r.preview.isEmpty ? chatTypeLabel(r.type) : r.preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 11.5, color: NebrasColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deletedBody() {
    final byOther = msg.deletedBy.isNotEmpty && msg.deletedBy != msg.senderId;
    final deleter = members[msg.deletedBy];
    final label = !byOther
        ? 'تم حذف هذه الرسالة'
        : (deleter?.isOwner ?? true)
            ? 'حذفها المالك 👑'
            : 'حذفها مشرف المجموعة ⭐';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.block, size: 15, color: NebrasColors.textMuted),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
              color: NebrasColors.textMuted,
              fontStyle: FontStyle.italic,
              fontSize: 13),
        ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    final att = msg.attachment;
    final caption = msg.text.trim();
    Widget content;
    switch (msg.type) {
      case ChatMessageType.text:
        content = Text(msg.text,
            style: const TextStyle(fontSize: 14.5, height: 1.45));
      case ChatMessageType.image:
        content = att == null
            ? _missingAttachment()
            : InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        ImageViewerPage(url: att.url, name: att.name))),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxHeight: 260, maxWidth: 260),
                    child: CachedNetworkImage(
                      imageUrl: att.url,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        width: 220,
                        height: 160,
                        color: NebrasColors.surfaceAlt,
                        child: const Center(
                            child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        width: 220,
                        height: 120,
                        color: NebrasColors.surfaceAlt,
                        child: const Icon(Icons.broken_image,
                            color: NebrasColors.textMuted),
                      ),
                    ),
                  ),
                ),
              );
      case ChatMessageType.video:
        content = att == null
            ? _missingAttachment()
            : InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) =>
                        VideoPlayerPage(url: att.url, name: att.name))),
                child: Container(
                  width: 240,
                  height: 140,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: NebrasColors.border),
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      const Icon(Icons.play_circle_fill,
                          size: 48, color: Colors.white70),
                      PositionedDirectional(
                        bottom: 6,
                        start: 8,
                        end: 8,
                        child: Text(
                          '${att.name}${att.size > 0 ? ' • ${formatBytes(att.size)}' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 10.5, color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ),
              );
      case ChatMessageType.audio:
      case ChatMessageType.voice:
        content = att == null
            ? _missingAttachment()
            : AudioBubblePlayer(
                url: att.url,
                durationMs: att.durationMs,
                isVoice: msg.type == ChatMessageType.voice,
              );
      case ChatMessageType.file:
        content = att == null
            ? _missingAttachment()
            : InkWell(
                onTap: () => launchUrl(Uri.parse(att.url),
                    mode: LaunchMode.externalApplication),
                child: Container(
                  width: 240,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.insert_drive_file,
                          color: NebrasColors.amber, size: 32),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(att.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600)),
                            if (att.size > 0)
                              Text(formatBytes(att.size),
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: NebrasColors.textMuted)),
                          ],
                        ),
                      ),
                      const Icon(Icons.download,
                          size: 18, color: NebrasColors.textMuted),
                    ],
                  ),
                ),
              );
    }

    if (msg.type != ChatMessageType.text && caption.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          content,
          const SizedBox(height: 6),
          Text(caption, style: const TextStyle(fontSize: 14, height: 1.4)),
        ],
      );
    }
    return content;
  }

  Widget _missingAttachment() {
    return const Text('مرفق غير متاح',
        style: TextStyle(color: NebrasColors.textMuted, fontSize: 12));
  }

  Widget _footer() {
    final time = intl.DateFormat('HH:mm').format(msg.createdAt);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(time,
            style:
                const TextStyle(fontSize: 10, color: NebrasColors.textMuted)),
        if (msg.isMine) ...[
          const SizedBox(width: 4),
          if (msg.pending)
            const Icon(Icons.access_time,
                size: 13, color: NebrasColors.textMuted)
          else
            Icon(
              readByAll ? Icons.done_all : Icons.done,
              size: 14,
              color: readByAll
                  ? const Color(0xFF38BDF8) // ✓✓ زرقاء: قرأها الجميع.
                  : NebrasColors.textMuted,
            ),
        ],
      ],
    );
  }
}
