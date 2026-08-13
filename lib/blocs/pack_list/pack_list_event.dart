import 'package:equatable/equatable.dart';

sealed class PackListEvent extends Equatable {
  const PackListEvent();

  @override
  List<Object?> get props => [];
}

class PackListLoadRequested extends PackListEvent {
  const PackListLoadRequested();
}

class PackCreated extends PackListEvent {
  const PackCreated(this.name, this.publisherName);

  final String name;
  final String publisherName;

  @override
  List<Object?> get props => [name, publisherName];
}

class PackRenamed extends PackListEvent {
  const PackRenamed(this.id, this.newName);

  final String id;
  final String newName;

  @override
  List<Object?> get props => [id, newName];
}

class PackDeleted extends PackListEvent {
  const PackDeleted(this.id);

  final String id;

  @override
  List<Object?> get props => [id];
}
