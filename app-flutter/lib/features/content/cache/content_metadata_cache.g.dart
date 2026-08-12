// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'content_metadata_cache.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ContentMetadataCacheEntryAdapter
    extends TypeAdapter<ContentMetadataCacheEntry> {
  @override
  final int typeId = 3;

  @override
  ContentMetadataCacheEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ContentMetadataCacheEntry(
      id: fields[0] as String,
      title: fields[1] as String,
      author: fields[2] as String,
      description: fields[3] as String,
      type: fields[4] as String,
      thumbnailUrl: fields[5] as String,
      section: fields[8] as String,
      createdAtMs: fields[11] as int,
      updatedAtMs: fields[12] as int,
      createdBy: fields[13] as String,
      cachedAtMs: fields[14] as int,
      sourceUrl: fields[6] as String?,
      sizeInBytes: fields[7] as int?,
      subSection: fields[9] as String?,
      sectionName: fields[10] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, ContentMetadataCacheEntry obj) {
    writer
      ..writeByte(15)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.author)
      ..writeByte(3)
      ..write(obj.description)
      ..writeByte(4)
      ..write(obj.type)
      ..writeByte(5)
      ..write(obj.thumbnailUrl)
      ..writeByte(6)
      ..write(obj.sourceUrl)
      ..writeByte(7)
      ..write(obj.sizeInBytes)
      ..writeByte(8)
      ..write(obj.section)
      ..writeByte(9)
      ..write(obj.subSection)
      ..writeByte(10)
      ..write(obj.sectionName)
      ..writeByte(11)
      ..write(obj.createdAtMs)
      ..writeByte(12)
      ..write(obj.updatedAtMs)
      ..writeByte(13)
      ..write(obj.createdBy)
      ..writeByte(14)
      ..write(obj.cachedAtMs);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContentMetadataCacheEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
