import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:infinite_listview/infinite_listview.dart';

typedef TextMapperE = String Function(String numberText);

class EditableNumberPicker extends StatefulWidget {
  /// Min value user can pick
  final int minValue;

  /// Max value user can pick
  final int maxValue;

  /// Currently selected value
  final int value;

  /// Called when selected value changes
  final ValueChanged<int> onChanged;

  /// Specifies how many items should be shown - defaults to 3
  final int itemCount;

  /// Step between elements. Only for integer datePicker
  /// Examples:
  /// if step is 100 the following elements may be 100, 200, 300...
  /// if min=0, max=6, step=3, then items will be 0, 3 and 6
  /// if min=0, max=5, step=3, then items will be 0 and 3.
  final int step;

  /// height of single item in pixels
  final double itemHeight;

  /// width of single item in pixels
  final double itemWidth;

  /// Direction of scrolling
  final Axis axis;

  /// Style of non-selected numbers. If null, it uses Theme's bodyText2
  final TextStyle? textStyle;

  /// Style of selected number. If null, it uses Theme's headline5 with accentColor
  final TextStyle? selectedTextStyle;

  /// Whether to trigger haptic pulses or not
  final bool haptics;

  /// Build the text of each item on the picker
  final TextMapperE? textMapper;

  /// Pads displayed integer values up to the length of maxValue
  final bool zeroPad;

  /// Decoration to apply to central box where the selected value is placed
  final Decoration? decoration;

  final bool infiniteLoop;

  const EditableNumberPicker({
    Key? key,
    required this.minValue,
    required this.maxValue,
    required this.value,
    required this.onChanged,
    this.itemCount = 3,
    this.step = 1,
    this.itemHeight = 50,
    this.itemWidth = 100,
    this.axis = Axis.vertical,
    this.textStyle,
    this.selectedTextStyle,
    this.haptics = false,
    this.decoration,
    this.zeroPad = false,
    this.textMapper,
    this.infiniteLoop = false,
  })  : assert(minValue <= value),
        assert(value <= maxValue),
        super(key: key);

  @override
  _EditableNumberPickerState createState() => _EditableNumberPickerState();
}

class _EditableNumberPickerState extends State<EditableNumberPicker> {
  late ScrollController _scrollController;

  late TextEditingController _inputController;
  late FocusNode _focusNode;

  late final KeyboardVisibilityController _keyboardController;
  late StreamSubscription<bool> keyboardSubscription;

  bool _numberPickerVisibility = true;
  bool _textFieldVisibility = false;

  @override
  void initState() {
    super.initState();

    final initialOffset =
        (widget.value - widget.minValue) ~/ widget.step * itemExtent;

    if (widget.infiniteLoop) {
      _scrollController =
          InfiniteScrollController(initialScrollOffset: initialOffset);
    } else {
      _scrollController = ScrollController(initialScrollOffset: initialOffset);
    }
    _scrollController.addListener(_scrollListener);

    _inputController = TextEditingController();
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        if (_inputController.text != '') {
          int newValue = _toValidItemValue(_inputController.text);
          if (widget.value != newValue) {
            _locateScroll(newValue);
            widget.onChanged(newValue);
            if (widget.haptics) {
              HapticFeedback.selectionClick();
            }
          }
        }

        setState(() {
          _numberPickerVisibility = true;
          _textFieldVisibility = false;
        });
      }
    });

    _keyboardController = KeyboardVisibilityController();
    keyboardSubscription = _keyboardController.onChange.listen((isVisible) {
      if (!isVisible) _focusNode.unfocus();
    });
  }

  void _scrollListener() {
    var indexOfMiddleElement = (_scrollController.offset / itemExtent).round();
    if (widget.infiniteLoop) {
      indexOfMiddleElement %= itemCount;
    } else {
      indexOfMiddleElement = indexOfMiddleElement.clamp(0, itemCount - 1);
    }
    final intValueInTheMiddle =
        _intValueFromIndex(indexOfMiddleElement + additionalItemsOnEachSide);

    if (widget.value != intValueInTheMiddle) {
      widget.onChanged(intValueInTheMiddle);
      if (widget.haptics) {
        HapticFeedback.selectionClick();
      }
    }
    Future.delayed(
      Duration(milliseconds: 100),
      () => _maybeCenterValue(),
    );
  }

  @override
  void didUpdateWidget(EditableNumberPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _maybeCenterValue();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _inputController.dispose();
    _focusNode.dispose();
    keyboardSubscription.cancel();
    super.dispose();
  }

  bool get isScrolling => _scrollController.position.isScrollingNotifier.value;

  double get itemExtent =>
      widget.axis == Axis.vertical ? widget.itemHeight : widget.itemWidth;

  int get itemCount => (widget.maxValue - widget.minValue) ~/ widget.step + 1;

  int get listItemsCount => itemCount + 2 * additionalItemsOnEachSide;

  int get additionalItemsOnEachSide => (widget.itemCount - 1) ~/ 2;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Visibility(
          child: SizedBox(
            width: widget.axis == Axis.vertical
                ? widget.itemWidth
                : widget.itemCount * widget.itemWidth,
            height: widget.axis == Axis.vertical
                ? widget.itemCount * widget.itemHeight
                : widget.itemHeight,
            child: NotificationListener<ScrollEndNotification>(
              onNotification: (not) {
                if (not.dragDetails?.primaryVelocity == 0) {
                  Future.microtask(() => _maybeCenterValue());
                }
                return true;
              },
              child: Stack(
                children: [
                  if (widget.infiniteLoop)
                    InfiniteListView.builder(
                      scrollDirection: widget.axis,
                      controller: _scrollController as InfiniteScrollController,
                      itemExtent: itemExtent,
                      itemBuilder: _itemBuilder,
                      padding: EdgeInsets.zero,
                    )
                  else
                    ListView.builder(
                      itemCount: listItemsCount,
                      scrollDirection: widget.axis,
                      controller: _scrollController,
                      itemExtent: itemExtent,
                      itemBuilder: _itemBuilder,
                      padding: EdgeInsets.zero,
                    ),
                  _NumberPickerSelectedItemDecoration(
                    axis: widget.axis,
                    itemExtent: itemExtent,
                    decoration: widget.decoration,
                  ),
                ],
              ),
            ),
          ),
          visible: _numberPickerVisibility,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
        ),
        Visibility(
          child: IntrinsicWidth(
            child: TextField(
              controller: _inputController,
              focusNode: _focusNode,
              onChanged: (val) {
                if (val != '' && int.parse(val) > widget.maxValue) {
                  _inputController.text = widget.maxValue.toString();
                  _selectEntireText();
                }
              },
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly
              ],
              toolbarOptions: ToolbarOptions(
                copy: false,
                paste: false,
                cut: false,
              ),
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                border: InputBorder.none,
              ),
              style: widget.selectedTextStyle ??
                  Theme.of(context).textTheme.headline5?.copyWith(
                      color: Theme.of(context).colorScheme.secondary),
            ),
          ),
          visible: _textFieldVisibility,
        ),
      ],
    );
  }

  Widget _itemBuilder(BuildContext context, int index) {
    final themeData = Theme.of(context);
    final defaultStyle = widget.textStyle ?? themeData.textTheme.bodyText2;
    final selectedStyle = widget.selectedTextStyle ??
        themeData.textTheme.headline5
            ?.copyWith(color: themeData.colorScheme.secondary);

    final value = _intValueFromIndex(index % itemCount);
    final isExtra = !widget.infiniteLoop &&
        (index < additionalItemsOnEachSide ||
            index >= listItemsCount - additionalItemsOnEachSide);
    final itemStyle = value == widget.value ? selectedStyle : defaultStyle;

    final child = isExtra
        ? SizedBox.shrink()
        : GestureDetector(
            onTap: () {
              if (value == widget.value) {
                setState(() {
                  _inputController.text = _getDisplayedValue(value);
                  _selectEntireText();
                  _numberPickerVisibility = false;
                  _textFieldVisibility = true;
                  _focusNode.requestFocus();
                });
              }
            },
            child: Text(
              _getDisplayedValue(value),
              textAlign: TextAlign.center,
              style: itemStyle,
            ),
          );

    return Container(
      width: widget.itemWidth,
      height: widget.itemHeight,
      alignment: Alignment.center,
      child: child,
    );
  }

  String _getDisplayedValue(int value) {
    final text = widget.zeroPad
        ? value.toString().padLeft(widget.maxValue.toString().length, '0')
        : value.toString();
    if (widget.textMapper != null) {
      return widget.textMapper!(text);
    } else {
      return text;
    }
  }

  int _intValueFromIndex(int index) {
    index -= additionalItemsOnEachSide;
    index %= itemCount;
    return widget.minValue + index * widget.step;
  }

  int _toValidItemValue(String value) {
    int newValue = int.parse(value);
    newValue = (newValue / widget.step).round() * widget.step;
    newValue = newValue.clamp(widget.minValue, widget.maxValue);
    return newValue;
  }

  void _maybeCenterValue() {
    if (_scrollController.hasClients && !isScrolling) {
      int diff = widget.value - widget.minValue;
      int index = diff ~/ widget.step;
      if (widget.infiniteLoop) {
        final offset = _scrollController.offset + 0.5 * itemExtent;
        final cycles = (offset / (itemCount * itemExtent)).floor();
        index += cycles * itemCount;
      }
      _scrollController.animateTo(
        index * itemExtent,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _locateScroll(int newValue) {
    if (_scrollController.hasClients && !isScrolling) {
      int diff = newValue - widget.minValue;
      int index = diff ~/ widget.step;
      if (widget.infiniteLoop) {
        final offset = _scrollController.offset + 0.5 * itemExtent;
        final cycles = (offset / (itemCount * itemExtent)).floor();
        index += cycles * itemCount;
      }
      _scrollController.jumpTo(index * itemExtent);
    }
  }

  void _selectEntireText() {
    _inputController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _inputController.text.length,
    );
  }
}

class _NumberPickerSelectedItemDecoration extends StatelessWidget {
  final Axis axis;
  final double itemExtent;
  final Decoration? decoration;

  const _NumberPickerSelectedItemDecoration({
    Key? key,
    required this.axis,
    required this.itemExtent,
    required this.decoration,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: IgnorePointer(
        child: Container(
          width: isVertical ? double.infinity : itemExtent,
          height: isVertical ? itemExtent : double.infinity,
          decoration: decoration,
        ),
      ),
    );
  }

  bool get isVertical => axis == Axis.vertical;
}
