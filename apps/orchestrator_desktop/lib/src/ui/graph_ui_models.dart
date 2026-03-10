import 'package:flutter/material.dart';

const double graphCanvasWidth = 5200;
const double graphCanvasHeight = 3200;
const double graphNodeWidth = 220;
const double graphNodeHeight = 140;
const double graphNodePortCenterY = 53;

class DeleteIntent extends Intent {
  const DeleteIntent();
}

class SelectAllIntent extends Intent {
  const SelectAllIntent();
}

class ClearSelectionIntent extends Intent {
  const ClearSelectionIntent();
}

class SaveGraphIntent extends Intent {
  const SaveGraphIntent();
}

class SaveLocalIntent extends Intent {
  const SaveLocalIntent();
}

class LoadLocalIntent extends Intent {
  const LoadLocalIntent();
}

extension IterableNullable<T> on Iterable<T> {
  T? get firstOrNull {
    if (isEmpty) {
      return null;
    }
    return first;
  }

  T? get lastOrNull {
    if (isEmpty) {
      return null;
    }
    return last;
  }
}
