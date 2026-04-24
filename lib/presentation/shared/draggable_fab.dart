import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pocketcrm/core/di/providers.dart';
import 'package:pocketcrm/core/utils/storage_service.dart';

class DraggableFabController {
  DraggableFabController();

  _DraggableFabState? _state;

  bool get isAttached => _state != null;

  void _attach(_DraggableFabState state) {
    _state = state;
  }

  void _detach(_DraggableFabState state) {
    if (_state == state) _state = null;
  }

  Future<void> reset({bool animate = true}) async {
    final state = _state;
    if (state == null) return;
    await state._reset(animate: animate);
  }
}

class DraggableFab extends ConsumerStatefulWidget {
  const DraggableFab({
    super.key,
    required this.pageKey,
    required this.child,
    this.controller,
    this.margin = 16,
    this.snapAnimationDuration = const Duration(milliseconds: 180),
    this.snapCurve = Curves.easeInOutCubicEmphasized,
    this.snapWithSpring = true,
    this.snapSpring = const SpringDescription(mass: 1, stiffness: 520, damping: 38),
    this.peekWidth = 14,
    this.peekHitWidth = 72,
    this.peekAnimationDuration = const Duration(milliseconds: 220),
    this.peekCurve = Curves.easeInOutCubicEmphasized,
    this.wakeAnimationDuration = const Duration(milliseconds: 220),
    this.wakeCurve = Curves.easeInOutCubicEmphasized,
    this.peekDelay = const Duration(milliseconds: 3200),
  });

  final String pageKey;
  final Widget child;
  final DraggableFabController? controller;
  final double margin;
  final Duration snapAnimationDuration;
  final Curve snapCurve;
  final bool snapWithSpring;
  final SpringDescription snapSpring;
  final double peekWidth;
  final double peekHitWidth;
  final Duration peekAnimationDuration;
  final Curve peekCurve;
  final Duration wakeAnimationDuration;
  final Curve wakeCurve;
  final Duration peekDelay;

  static bool _sessionPeeked = false;
  static Object? _activeInstance;

  static void resetSessionStateForTest() {
    _sessionPeeked = false;
    _activeInstance = null;
  }

  static const String storageKeyGlobal = 'draggable_fab:pos:global';
  static String storageKeyLegacyForPage(String pageKey) =>
      'draggable_fab:pos:$pageKey';

  static Future<void> clearStoredPosition({
    required StorageService storage,
    required String pageKey,
  }) async {
    await storage.delete(key: storageKeyGlobal);
    await storage.delete(key: storageKeyLegacyForPage(pageKey));
  }

  @override
  ConsumerState<DraggableFab> createState() => _DraggableFabState();
}

class _DraggableFabState extends ConsumerState<DraggableFab>
    with TickerProviderStateMixin {
  final Object _instanceKey = Object();
  final GlobalKey _fabKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  BuildContext? _overlayContextForMedia;
  ModalRoute<dynamic>? _route;
  Animation<double>? _routeAnimation;
  bool _lastRouteCurrent = true;

  Offset _topLeft = Offset.zero;
  bool _dragging = false;
  bool _loaded = false;
  bool _storageLoaded = false;
  bool _peeked = false;
  _FabSide _side = _FabSide.right;
  double _yFraction = 1;

  Size? _lastMediaSize;
  EdgeInsets? _lastViewInsets;
  Offset? _dragStartPointerGlobal;
  Offset? _dragStartTopLeft;
  Size? _fabSize;
  Timer? _peekTimer;
  int _sizeProbeTries = 0;
  bool _debugPrinted = false;

  late final AnimationController _moveController;
  Offset? _moveBegin;
  Offset? _moveEnd;
  late final AnimationController _peekController;

  @override
  void initState() {
    super.initState();
    DraggableFab._activeInstance = _instanceKey;
    widget.controller?._attach(this);
    _moveController = AnimationController.unbounded(vsync: this);
    _moveController.addListener(() {
      final begin = _moveBegin;
      final end = _moveEnd;
      if (begin == null || end == null) return;
      if (!_isRouteCurrent) return;
      final t = _moveController.value.clamp(0.0, 1.0);
      _topLeft = Offset.lerp(begin, end, t) ?? _topLeft;
      _markOverlayNeedsBuild();
    });
    _peekController = AnimationController(
      vsync: this,
      lowerBound: 0,
      upperBound: 1,
      value: DraggableFab._sessionPeeked ? 0 : 1,
    );
    _peekController.addListener(() {
      if (!_loaded) return;
      _markOverlayNeedsBuild();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _ensureOverlayInserted();
        _ensureFabSizeSoon();
      }
    });
  }

  @override
  void didUpdateWidget(covariant DraggableFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    if (oldWidget.child != widget.child) _ensureFabSizeSoon();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _markOverlayNeedsBuild();
    });
  }

  @override
  void dispose() {
    widget.controller?._detach(this);
    if (DraggableFab._activeInstance == _instanceKey) {
      DraggableFab._activeInstance = null;
    }
    _peekTimer?.cancel();
    _routeAnimation?.removeListener(_handleRouteAnimationTick);
    _overlayEntry?.remove();
    _overlayEntry = null;
    _moveController.dispose();
    _peekController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isRouteCurrent) DraggableFab._activeInstance = _instanceKey;
    final nextRoute = ModalRoute.of(context);
    if (nextRoute != _route) {
      _routeAnimation?.removeListener(_handleRouteAnimationTick);
      _route = nextRoute;
      _routeAnimation = nextRoute?.animation;
      _routeAnimation?.addListener(_handleRouteAnimationTick);
      _lastRouteCurrent = _isRouteCurrent;
      if (_isRouteCurrent) DraggableFab._activeInstance = _instanceKey;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _markOverlayNeedsBuild();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _ensureOverlayInserted();
        _ensureFabSizeSoon();
      }
    });
  }

  bool get _isRouteCurrent => _route == null || _route!.isCurrent;
  bool get _isPeeking => _peekController.value < 0.999;

  void _handleRouteAnimationTick() {
    final current = _isRouteCurrent;
    if (current && !_lastRouteCurrent) {
      DraggableFab._activeInstance = _instanceKey;
      unawaited(_onRouteEnter());
    } else if (!current && _lastRouteCurrent) {
      _peekTimer?.cancel();
      final v = _peekController.value;
      if (_peekController.isAnimating || (v > 0.001 && v < 0.999)) {
        _peekController.stop();
        final next = v >= 0.5 ? 1.0 : 0.0;
        _peekController.value = next;
        _peeked = next == 0.0;
        DraggableFab._sessionPeeked = _peeked;
      }
    }
    _lastRouteCurrent = current;
    _markOverlayNeedsBuild();
  }

  void _markOverlayNeedsBuild() {
    _overlayEntry?.markNeedsBuild();
  }

  void _ensureOverlayInserted() {
    if (_overlayEntry != null) return;
    final overlay = Overlay.of(context);
    _overlayContextForMedia = overlay.context;
    _overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        final visible = _loaded &&
            _isRouteCurrent &&
            identical(DraggableFab._activeInstance, _instanceKey);
        final fabSize = _fabSize ?? const Size(56, 56);
        final isPeeking = _peekController.value < 0.999;
        final peekEdgeShift = isPeeking
            ? (widget.margin * (1 - _peekController.value) * (_side == _FabSide.left ? -1 : 1))
            : 0.0;
        final hitWidth = isPeeking
            ? widget.peekHitWidth < fabSize.width
                ? fabSize.width
                : widget.peekHitWidth
            : fabSize.width;
        final shiftX = isPeeking && _side == _FabSide.right && hitWidth > fabSize.width
            ? hitWidth - fabSize.width
            : 0.0;
        final renderTopLeft =
            visible ? _topLeft + Offset(peekEdgeShift, 0) - Offset(shiftX, 0) : Offset.zero;
        return Positioned.fill(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: renderTopLeft.dx,
                top: renderTopLeft.dy,
                child: IgnorePointer(
                  ignoring: !visible,
                  child: Opacity(
                    opacity: visible ? 1 : 0,
                    child: _buildOverlayFab(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    overlay.insert(_overlayEntry!);
    _markOverlayNeedsBuild();
  }

  Widget _buildOverlayFab() {
    final fabSize = _fabSize ?? const Size(56, 56);
    final isPeeking = _peekController.value < 0.999;
    final minFactor = (widget.peekWidth / fabSize.width).clamp(0.0, 1.0);
    final widthFactor = minFactor + (1 - minFactor) * _peekController.value;
    final alignment =
        _side == _FabSide.left ? Alignment.centerLeft : Alignment.centerRight;
    final hitWidth = isPeeking
        ? widget.peekHitWidth < fabSize.width
            ? fabSize.width
            : widget.peekHitWidth
        : fabSize.width;

    return RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isPeeking ? _wake : null,
        onLongPressStart: (details) {
          _peekTimer?.cancel();
          if (!_loaded) return;
          _peeked = false;
          _peekController.stop();
          _peekController.value = 1;
          _stopMoveAnimation();
          _dragStartPointerGlobal = details.globalPosition;
          _dragStartTopLeft = _topLeft;
          _dragging = true;
          _markOverlayNeedsBuild();
        },
        onLongPressMoveUpdate: (details) {
          if (!_loaded) return;
          final startPointer = _dragStartPointerGlobal;
          final startTopLeft = _dragStartTopLeft;
          final size = _fabSize;
          if (startPointer == null || startTopLeft == null || size == null) return;

          final desired = startTopLeft + (details.globalPosition - startPointer);
          final bounds = _computeBoundsFor(size);
          final clamped = Offset(
            desired.dx.clamp(bounds.minX, bounds.maxX),
            desired.dy.clamp(bounds.minY, bounds.maxY),
          );
          if (clamped == _topLeft) return;
          _topLeft = clamped;
          _markOverlayNeedsBuild();
        },
        onLongPressEnd: (details) async {
          if (!_loaded) return;
          _dragging = false;
          _dragStartPointerGlobal = null;
          _dragStartTopLeft = null;

          final size = _fabSize;
          if (size == null) return;

          final bounds = _computeBoundsFor(size);
          final clamped = Offset(
            _topLeft.dx.clamp(bounds.minX, bounds.maxX),
            _topLeft.dy.clamp(bounds.minY, bounds.maxY),
          );

          final centerX = clamped.dx + size.width / 2;
          final side =
              centerX < _mediaSize(context).width / 2 ? _FabSide.left : _FabSide.right;
          final snapX = side == _FabSide.left ? bounds.minX : bounds.maxX;
          final snapped = Offset(snapX, clamped.dy);

          _side = side;
          _yFraction = _computeYFraction(bounds: bounds, top: snapped.dy);
          _peeked = false;
          _peekController.stop();
          _peekController.value = 1;

          _stopMoveAnimation();
          _topLeft = clamped;
          _markOverlayNeedsBuild();
          if (snapped != clamped) unawaited(_animateTo(snapped));
          await _persistCurrent();
          _schedulePeek();
        },
        child: SizedBox(
          width: hitWidth,
          height: fabSize.height,
          child: Align(
            alignment: alignment,
            child: SizedBox(
              width: isPeeking ? fabSize.width * widthFactor : fabSize.width,
              height: fabSize.height,
              child: ClipRRect(
                clipBehavior: Clip.antiAlias,
                borderRadius: _side == _FabSide.left
                    ? BorderRadius.only(
                        topLeft: Radius.circular(16 * _peekController.value),
                        bottomLeft: Radius.circular(16 * _peekController.value),
                        topRight: const Radius.circular(16),
                        bottomRight: const Radius.circular(16),
                      )
                    : BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        bottomLeft: const Radius.circular(16),
                        topRight: Radius.circular(16 * _peekController.value),
                        bottomRight: Radius.circular(16 * _peekController.value),
                      ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (isPeeking)
                      Material(
                        color: Theme.of(context).colorScheme.primary,
                        elevation: 6,
                        shadowColor: Colors.black54,
                      ),
                    Opacity(
                      opacity: isPeeking ? 0 : 1,
                      child: Align(
                        alignment: alignment,
                        child: SizedBox(
                          width: fabSize.width,
                          height: fabSize.height,
                          child: KeyedSubtree(
                            key: _fabKey,
                            child: AnimatedScale(
                              scale: _dragging ? 1.06 : 1,
                              duration: const Duration(milliseconds: 120),
                              curve: Curves.easeOut,
                              child: AbsorbPointer(
                                absorbing: isPeeking,
                                child: widget.child,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _ensureFabSizeSoon() {
    if (_sizeProbeTries > 30) {
      if (!_loaded && _fabSize == null) {
        const guess = Size(56, 56);
        _fabSize = guess;
        final bounds = _computeBoundsFor(guess);
        _side = _FabSide.right;
        _yFraction = 1;
        _peeked = DraggableFab._sessionPeeked;
        _peekController.stop();
        _peekController.value = _peeked ? 0 : 1;
        _topLeft = Offset(bounds.maxX, bounds.maxY);
        _loaded = true;
        _markOverlayNeedsBuild();
        _schedulePeek();
        unawaited(_loadAndInitPosition());
        unawaited(_ensureInBoundsAndPersist());
      }
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ensureOverlayInserted();
      final box = _renderFabBox();
      if (box == null) {
        _sizeProbeTries++;
        _ensureFabSizeSoon();
        return;
      }
      _sizeProbeTries = 0;
      final next = box.size;
      if (_fabSize == next && _loaded) return;
      _fabSize = next;
      if (!_loaded) {
        final bounds = _computeBoundsFor(next);
        _side = _FabSide.right;
        _yFraction = 1;
        _peeked = DraggableFab._sessionPeeked;
        _peekController.stop();
        _peekController.value = _peeked ? 0 : 1;
        _topLeft = Offset(bounds.maxX, bounds.maxY);
        _loaded = true;
        _markOverlayNeedsBuild();
        _schedulePeek();
        unawaited(_loadAndInitPosition());
      }
      unawaited(_ensureInBoundsAndPersist());
    });
  }

  RenderBox? _renderFabBox() {
    final ctx = _fabKey.currentContext;
    if (ctx == null) return null;
    final ro = ctx.findRenderObject();
    if (ro is! RenderBox) return null;
    if (!ro.hasSize) return null;
    return ro;
  }

  Future<void> _loadAndInitPosition() async {
    if (_storageLoaded) return;
    _storageLoaded = true;
    final size = _fabSize;
    if (size == null) return;
    final storage = ref.read(storageServiceProvider);
    try {
      final globalRaw = await storage.read(key: DraggableFab.storageKeyGlobal);
      final hadPersistedPeek = _rawHasPeekTrue(globalRaw);
      final decodedGlobal = _decodePersisted(globalRaw);
      if (!mounted) return;
      if (decodedGlobal != null) {
        _side = decodedGlobal.side;
        _yFraction = decodedGlobal.yFraction;
        _peeked = DraggableFab._sessionPeeked;
        _peekController.stop();
        _peekController.value = _peeked ? 0 : 1;
        if (hadPersistedPeek) unawaited(_persistCurrent());
      } else {
        final legacyKey = DraggableFab.storageKeyLegacyForPage(widget.pageKey);
        final legacyRaw = await storage.read(key: legacyKey);
        final legacyDelta = _decodeOffset(legacyRaw);
        if (!mounted) return;
        if (legacyDelta != null) {
          final base = _defaultBaseTopLeft(size);
          final legacyTopLeft = base + legacyDelta;
          final bounds = _computeBoundsFor(size);
          final clamped = Offset(
            legacyTopLeft.dx.clamp(bounds.minX, bounds.maxX),
            legacyTopLeft.dy.clamp(bounds.minY, bounds.maxY),
          );

          final centerX = clamped.dx + size.width / 2;
          _side = centerX < _mediaSize(context).width / 2
              ? _FabSide.left
              : _FabSide.right;
          final snapX = _side == _FabSide.left ? bounds.minX : bounds.maxX;
          final snapped = Offset(snapX, clamped.dy);
          _yFraction = _computeYFraction(bounds: bounds, top: snapped.dy);
          _peeked = DraggableFab._sessionPeeked;
          _peekController.stop();
          _peekController.value = _peeked ? 0 : 1;
          await storage.write(
            key: DraggableFab.storageKeyGlobal,
            value: _encodePersisted(
              _PersistedFabPos(
                side: _side,
                yFraction: _yFraction,
                peeked: _peeked,
              ),
            ),
          );
          await storage.delete(key: legacyKey);
        }
      }
    } catch (_) {
      return;
    }
    _peeked = DraggableFab._sessionPeeked;
    _peekController.stop();
    _peekController.value = _peeked ? 0 : 1;
    _topLeft = _computeTopLeft(peeked: false);
    _markOverlayNeedsBuild();
    unawaited(_ensureInBoundsAndPersist());
    _schedulePeek();
  }

  Future<void> _persistCurrent() async {
    try {
      if (!mounted) return;
      final storage = ref.read(storageServiceProvider);
      await storage.write(
        key: DraggableFab.storageKeyGlobal,
        value: _encodePersisted(
          _PersistedFabPos(side: _side, yFraction: _yFraction, peeked: _peeked),
        ),
      );
    } catch (_) {}
  }

  Future<void> _onRouteEnter() async {
    if (!_loaded) return;
    final size = _fabSize;
    if (size == null) return;
    _peekTimer?.cancel();
    _stopMoveAnimation();
    _peeked = DraggableFab._sessionPeeked;
    _peekController.stop();
    _peekController.value = _peeked ? 0 : 1;
    _topLeft = _computeTopLeft(peeked: false);
    _markOverlayNeedsBuild();
    await _persistCurrent();
    _schedulePeek();
  }

  Offset _defaultBaseTopLeft(Size widgetSize) {
    final bounds = _computeBoundsFor(widgetSize);
    return Offset(bounds.maxX, bounds.maxY);
  }

  void _schedulePeek() {
    _peekTimer?.cancel();
    if (!_loaded) return;
    if (_dragging) return;
    if (_isPeeking) return;
    _peekTimer = Timer(widget.peekDelay, () {
      if (!mounted) return;
      if (!_isRouteCurrent) return;
      if (_dragging) return;
      unawaited(_peek());
    });
  }

  Future<void> _peek() async {
    final size = _fabSize;
    if (size == null) return;
    if (_isPeeking) return;
    _peeked = true;
    DraggableFab._sessionPeeked = true;
    _peekController.stop();
    try {
      await _peekController.animateTo(
        0,
        duration: widget.peekAnimationDuration,
        curve: widget.peekCurve,
      );
    } catch (_) {}
    if (!mounted) return;
    _peekController.value = 0;
    _markOverlayNeedsBuild();
    await _persistCurrent();
  }

  Future<void> _wake() async {
    _peekTimer?.cancel();
    final size = _fabSize;
    if (size == null) return;
    if (!_isPeeking) return;
    _peeked = false;
    DraggableFab._sessionPeeked = false;
    _peekController.stop();
    try {
      await _peekController.animateTo(
        1,
        duration: widget.wakeAnimationDuration,
        curve: widget.wakeCurve,
      );
    } catch (_) {}
    if (!mounted) return;
    _peekController.value = 1;
    _markOverlayNeedsBuild();
    await _persistCurrent();
    _schedulePeek();
  }

  _Bounds _computeBoundsFor(Size widgetSize) {
    final screen = _mediaSize(context);
    final padding = _safePadding(context);
    final viewInsets = _viewInsets(context);
    return _computeBounds(
      screen: screen,
      padding: padding,
      viewInsets: viewInsets,
      widgetSize: widgetSize,
      margin: widget.margin,
    );
  }

  double _computeYFraction({required _Bounds bounds, required double top}) {
    final denom = bounds.maxY - bounds.minY;
    if (denom <= 0) return 0;
    return ((top - bounds.minY) / denom).clamp(0, 1);
  }

  Offset _computeTopLeft({required bool peeked}) {
    final size = _fabSize;
    if (size == null) return _topLeft;
    final bounds = _computeBoundsFor(size);
    final top = bounds.minY + _yFraction * (bounds.maxY - bounds.minY);
    final x = _side == _FabSide.left ? bounds.minX : bounds.maxX;
    return Offset(x, top);
  }

  Future<void> _ensureInBoundsAndPersist() async {
    if (!mounted) return;
    if (_dragging) return;
    final size = _fabSize;
    if (size == null) return;

    final bounds = _computeBoundsFor(size);
    assert(() {
      if (_loaded && !_debugPrinted) {
        _debugPrinted = true;
        final screen = _mediaSize(context);
        final padding = _safePadding(context);
        final insets = _viewInsets(context);
        debugPrint(
          'DraggableFab(${widget.pageKey}): screen=$screen padding=$padding insets=$insets size=$size bounds=(${bounds.minX},${bounds.minY})-(${bounds.maxX},${bounds.maxY}) topLeft=$_topLeft peeked=$_peeked',
        );
      }
      return true;
    }());
    final awake = _computeTopLeft(peeked: false);
    final clampedAwake = Offset(
      awake.dx.clamp(bounds.minX, bounds.maxX),
      awake.dy.clamp(bounds.minY, bounds.maxY),
    );

    final centerX = clampedAwake.dx + size.width / 2;
    final side =
        centerX < _mediaSize(context).width / 2 ? _FabSide.left : _FabSide.right;
    final snapX = side == _FabSide.left ? bounds.minX : bounds.maxX;
    final snappedAwake = Offset(snapX, clampedAwake.dy);

    final nextFraction = _computeYFraction(bounds: bounds, top: snappedAwake.dy);
    final changed = side != _side || nextFraction != _yFraction;
    _side = side;
    _yFraction = nextFraction;

    final nextTopLeft = _computeTopLeft(peeked: false);
    if (nextTopLeft != _topLeft) {
      _topLeft = nextTopLeft;
      _markOverlayNeedsBuild();
    }
    if (changed) await _persistCurrent();
  }

  void _stopMoveAnimation() {
    if (_moveController.isAnimating) _moveController.stop();
    _moveBegin = null;
    _moveEnd = null;
  }

  Future<void> _animateTo(Offset target) async {
    _stopMoveAnimation();
    _moveBegin = _topLeft;
    _moveEnd = target;
    _moveController.value = 0;
    try {
      if (widget.snapWithSpring) {
        await _moveController
            .animateWith(SpringSimulation(widget.snapSpring, 0, 1, 0))
            .orCancel;
      } else {
        await _moveController
            .animateTo(
              1,
              duration: widget.snapAnimationDuration,
              curve: widget.snapCurve,
            )
            .orCancel;
      }
    } catch (_) {}
    if (!mounted) return;
    _topLeft = target;
    _stopMoveAnimation();
    _markOverlayNeedsBuild();
  }

  Size _mediaSize(BuildContext context) {
    final overlayCtx = _overlayContextForMedia;
    if (overlayCtx != null) {
      final ro = overlayCtx.findRenderObject();
      if (ro is RenderBox && ro.hasSize) return ro.size;
    }
    return MediaQuery.sizeOf(overlayCtx ?? context);
  }

  EdgeInsets _safePadding(BuildContext context) =>
      MediaQuery.paddingOf(_overlayContextForMedia ?? context);

  EdgeInsets _viewInsets(BuildContext context) =>
      MediaQuery.viewInsetsOf(_overlayContextForMedia ?? context);

  _Bounds _computeBounds({
    required Size screen,
    required EdgeInsets padding,
    required EdgeInsets viewInsets,
    required Size widgetSize,
    required double margin,
  }) {
    final minX = padding.left + margin;
    final maxX = screen.width - padding.right - margin - widgetSize.width;

    final minY = padding.top + margin;
    final bottomSafe = screen.height - padding.bottom - viewInsets.bottom;
    final maxY = bottomSafe - margin - widgetSize.height;

    return _Bounds(
      minX: minX,
      maxX: maxX < minX ? minX : maxX,
      minY: minY,
      maxY: maxY < minY ? minY : maxY,
    );
  }

  Future<void> _reset({required bool animate}) async {
    final storage = ref.read(storageServiceProvider);
    try {
      await storage.delete(key: DraggableFab.storageKeyGlobal);
      await storage.delete(key: DraggableFab.storageKeyLegacyForPage(widget.pageKey));
    } catch (_) {}

    _peekTimer?.cancel();
    _peeked = false;
    DraggableFab._sessionPeeked = false;
    _peekController.stop();
    _peekController.value = 1;

    final size = _fabSize;
    if (size == null) return;
    final bounds = _computeBoundsFor(size);
    _side = _FabSide.right;
    _yFraction = 1;
    final target = Offset(bounds.maxX, bounds.maxY);

    if (animate) {
      await _animateTo(target);
    } else {
      _stopMoveAnimation();
    }
    _topLeft = target;
    _markOverlayNeedsBuild();
  }

  @override
  Widget build(BuildContext context) {
    final mediaSize = _mediaSize(context);
    final viewInsets = _viewInsets(context);
    final shouldReclamp = (_lastMediaSize != null && _lastMediaSize != mediaSize) ||
        (_lastViewInsets != null && _lastViewInsets != viewInsets);
    if (shouldReclamp && _loaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_ensureInBoundsAndPersist());
      });
    }
    _lastMediaSize = mediaSize;
    _lastViewInsets = viewInsets;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _ensureOverlayInserted();
        _ensureFabSizeSoon();
      }
    });

    return const SizedBox.shrink();
  }
}

class _Bounds {
  const _Bounds({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  final double minX;
  final double maxX;
  final double minY;
  final double maxY;
}

Offset? _decodeOffset(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);
    final dx = map['dx'];
    final dy = map['dy'];
    if (dx is num && dy is num) return Offset(dx.toDouble(), dy.toDouble());
  } catch (_) {}
  return null;
}

enum _FabSide { left, right }

class _PersistedFabPos {
  const _PersistedFabPos({
    required this.side,
    required this.yFraction,
    required this.peeked,
  });

  final _FabSide side;
  final double yFraction;
  final bool peeked;
}

String _encodePersisted(_PersistedFabPos pos) => jsonEncode(<String, dynamic>{
      'v': 2,
      'side': pos.side == _FabSide.left ? 'l' : 'r',
      'y': pos.yFraction,
      'peek': false,
    });

_PersistedFabPos? _decodePersisted(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);
    if (map['v'] != 2) return null;
    final sideRaw = map['side'];
    final yRaw = map['y'];
    if (sideRaw is! String || yRaw is! num) return null;
    final side = sideRaw == 'l' ? _FabSide.left : _FabSide.right;
    final y = yRaw.toDouble().clamp(0.0, 1.0);
    return _PersistedFabPos(side: side, yFraction: y, peeked: false);
  } catch (_) {
    return null;
  }
}

bool _rawHasPeekTrue(String? raw) {
  if (raw == null || raw.trim().isEmpty) return false;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return false;
    final map = Map<String, dynamic>.from(decoded);
    if (map['v'] != 2) return false;
    return map['peek'] == true;
  } catch (_) {
    return false;
  }
}
