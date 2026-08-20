import 'package:equatable/equatable.dart';

sealed class ImportEvent extends Equatable {
  const ImportEvent();

  @override
  List<Object?> get props => [];
}

class PickStaticImagesRequested extends ImportEvent {
  const PickStaticImagesRequested();
}

class PickGifRequested extends ImportEvent {
  const PickGifRequested();
}

class LinkUrlSubmitted extends ImportEvent {
  const LinkUrlSubmitted(this.url);

  final String url;

  @override
  List<Object?> get props => [url];
}

class LinkThumbnailConfirmed extends ImportEvent {
  const LinkThumbnailConfirmed(this.selectedPaths);

  final List<String> selectedPaths;

  @override
  List<Object?> get props => [selectedPaths];
}
