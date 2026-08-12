// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_item_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DownloadItemModelAdapter extends TypeAdapter<DownloadItemModel> {
  @override
  final int typeId = 1;

  @override
  DownloadItemModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DownloadItemModel(
      contentId: fields[0] as String,
      url: fields[1] as String,
      localPath: fields[2] as String,
      progress: fields[3] as double,
      status: fields[4] as String,
      totalBytes: fields[5] as int,
      contentType: fields[6] as String,
      title: fields[7] as String,
      imageUrl: fields[8] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, DownloadItemModel obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.contentId)
      ..writeByte(1)
      ..write(obj.url)
      ..writeByte(2)
      ..write(obj.localPath)
      ..writeByte(3)
      ..write(obj.progress)
      ..writeByte(4)
      ..write(obj.status)
      ..writeByte(5)
      ..write(obj.totalBytes)
      ..writeByte(6)
      ..write(obj.contentType)
      ..writeByte(7)
      ..write(obj.title)
      ..writeByte(8)
      ..write(obj.imageUrl);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadItemModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
