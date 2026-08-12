// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'saved_item_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SavedItemModelAdapter extends TypeAdapter<SavedItemModel> {
  @override
  final int typeId = 0;

  @override
  SavedItemModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SavedItemModel(
      id: fields[0] as String,
      title: fields[1] as String,
      imageUrl: fields[2] as String?,
      contentType: fields[3] as String,
      savedAt: fields[4] as DateTime,
    );
  }

  @override
  void write(BinaryWriter writer, SavedItemModel obj) {
    writer
      ..writeByte(5)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.imageUrl)
      ..writeByte(3)
      ..write(obj.contentType)
      ..writeByte(4)
      ..write(obj.savedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SavedItemModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
