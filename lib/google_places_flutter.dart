library google_places_flutter;


import 'package:flutter/material.dart';
import 'package:google_places_flutter/model/place_details.dart';
import 'package:google_places_flutter/model/prediction.dart';

import 'package:dio/dio.dart';
import 'package:rxdart/rxdart.dart';

import 'DioErrorHandler.dart';

class GooglePlaceAutoCompleteTextField extends StatefulWidget {
  final InputDecoration inputDecoration;
  final ItemClick? itemClick;
  final GetPlaceDetailswWithLatLng? getPlaceDetailWithLatLng;
  final bool isLatLngRequired;
  final TextStyle textStyle;
  final String googleAPIKey;
  final int debounceTime;
  final List<String> countries;
  final TextEditingController textEditingController;
  final ListItemBuilder? itemBuilder;
  final Widget? seperatedBuilder;
  final BoxDecoration? boxDecoration;
  final bool isCrossBtnShown;
  final bool showError;
  final EdgeInsetsGeometry padding;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;

  GooglePlaceAutoCompleteTextField({
    Key? key,
    required this.textEditingController,
    required this.googleAPIKey,
    this.debounceTime = 600,
    this.inputDecoration = const InputDecoration(),
    this.itemClick,
    this.isLatLngRequired = true,
    this.textStyle = const TextStyle(),
    this.countries = const <String>[],
    this.getPlaceDetailWithLatLng,
    this.itemBuilder,
    this.boxDecoration,
    this.isCrossBtnShown = true,
    this.seperatedBuilder,
    this.showError = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    this.onChanged,
    this.focusNode,
  }): super(key: key);

  @override
  _GooglePlaceAutoCompleteTextFieldState createState() =>
      _GooglePlaceAutoCompleteTextFieldState();
}

class _GooglePlaceAutoCompleteTextFieldState
    extends State<GooglePlaceAutoCompleteTextField> {
  final subject = new PublishSubject<String>();
  OverlayEntry? _overlayEntry;
  List<Prediction> alPredictions = [];

  TextEditingController controller = TextEditingController();
  final LayerLink _layerLink = LayerLink();
  bool isSearched = false;

  bool isCrossBtn = true;
  late var _dio;

  CancelToken? _cancelToken = CancelToken();

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Container(
        padding: widget.padding,
        alignment: Alignment.centerLeft,
        decoration: widget.boxDecoration ??
            BoxDecoration(
                shape: BoxShape.rectangle,
                border: Border.all(color: Colors.grey, width: 0.6),
                borderRadius: BorderRadius.all(Radius.circular(10))),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextFormField(
                focusNode: widget.focusNode,
                decoration: widget.inputDecoration,
                style: widget.textStyle,
                controller: widget.textEditingController,
                onChanged: (string) {
                  subject.add(string);
                  if (widget.isCrossBtnShown) {
                    isCrossBtn = string.isNotEmpty ? true : false;
                    setState(() {});
                  }
                  widget.onChanged?.call(string);
                },
              ),
            ),
            (!widget.isCrossBtnShown)
                ? SizedBox()
                : isCrossBtn && _showCrossIconWidget()
                    ? IconButton(onPressed: clearData, icon: Icon(Icons.close))
                    : SizedBox()
          ],
        ),
      ),
    );
  }

  getLocation(String text) async {
    String url =
        "https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$text&key=${widget.googleAPIKey}";

    if (widget.countries.isNotEmpty) {
      // in

      for (int i = 0; i < widget.countries.length; i++) {
        String country = widget.countries[i];

        if (i == 0) {
          url = url + "&components=country:$country";
        } else {
          url = url + "|" + "country:" + country;
        }
      }
    }

    if (_cancelToken?.isCancelled == false) {
      _cancelToken?.cancel();
      _cancelToken = CancelToken();
    }


    try {
      Response response = await _dio.get(url);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      Map map = response.data;
      if (map.containsKey("error_message")) {
        throw response.data;
      }

      PlacesAutocompleteResponse subscriptionResponse =
          PlacesAutocompleteResponse.fromJson(response.data);

      if (text.length == 0) {
        alPredictions.clear();
        this._overlayEntry!.remove();
        return;
      }

      isSearched = false;
      alPredictions.clear();
      if (subscriptionResponse.predictions!.length > 0 && (widget.textEditingController.text.toString().trim()).isNotEmpty) {
        alPredictions.addAll(subscriptionResponse.predictions!);
      }


      this._overlayEntry = null;
      this._overlayEntry = this._createOverlayEntry();
      Overlay.of(context).insert(this._overlayEntry!);
    } catch (e) {
      var errorHandler = ErrorHandler.internal().handleError(e);
      if (mounted) {
        _showSnackBar("${errorHandler.message}");
      }
    }
  }

  @override
  void initState() {
    super.initState();
    widget.textEditingController.addListener(() {
      if(widget.textEditingController.text.isEmpty){
        removeOverlay();
      }
    });
    _dio = Dio();
    subject.stream
        .distinct()
        .debounceTime(Duration(milliseconds: widget.debounceTime))
        .listen(textChanged);
  }

  textChanged(String text) async {
    getLocation(text);
  }

  OverlayEntry? _createOverlayEntry() {
    if (mounted && context.findRenderObject() != null) {
      RenderBox renderBox = context.findRenderObject() as RenderBox;
      var size = renderBox.size;
      var offset = renderBox.localToGlobal(Offset.zero);
      return OverlayEntry(
          builder: (context) => Positioned(
                left: offset.dx,
                top: size.height + offset.dy,
                width: size.width,
                child: CompositedTransformFollower(
                  showWhenUnlinked: false,
                  link: this._layerLink,
                  offset: Offset(0.0, size.height + 5.0),
                  child: Material(
                      child: ListView.separated(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: alPredictions.length,
                    separatorBuilder: (context, pos) =>
                        widget.seperatedBuilder ?? SizedBox(),
                    itemBuilder: (BuildContext context, int index) {
                      return InkWell(
                        onTap: () {
                          var selectedData = alPredictions[index];
                          if (index < alPredictions.length) {
                            widget.itemClick!(selectedData);

                            if (widget.isLatLngRequired) {
                              getPlaceDetailsFromPlaceId(selectedData);
                            }
                            removeOverlay();
                          }
                        },
                        child: widget.itemBuilder != null
                            ? widget.itemBuilder!(
                                context, index, alPredictions[index])
                            : Container(
                                padding: EdgeInsets.all(10),
                                child: Text(alPredictions[index].description!)),
                      );
                    },
                  )),
                ),
              ));
    }
    return null;
  }

  removeOverlay() {
    if (mounted) {
      alPredictions.clear();
      this._overlayEntry = this._createOverlayEntry();
      Overlay.of(context).insert(this._overlayEntry!);
      this._overlayEntry!.markNeedsBuild();
    }
    }

  Future<Response?> getPlaceDetailsFromPlaceId(Prediction prediction) async {
    //String key = GlobalConfiguration().getString('google_maps_key');

    var url =
        "https://maps.googleapis.com/maps/api/place/details/json?placeid=${prediction.placeId}&key=${widget.googleAPIKey}";
    Response response = await Dio().get(
      url,
    );

    PlaceDetails placeDetails = PlaceDetails.fromJson(response.data);

    prediction.lat = placeDetails.result!.geometry!.location!.lat.toString();
    prediction.lng = placeDetails.result!.geometry!.location!.lng.toString();

    widget.getPlaceDetailWithLatLng!(prediction);
    return null;
  }

  void clearData() {
    widget.textEditingController.clear();
    if (_cancelToken?.isCancelled == false) {
      _cancelToken?.cancel();
    }

    setState(() {
      alPredictions.clear();
      isCrossBtn = false;
    });

    if (this._overlayEntry != null) {
      try {
        this._overlayEntry?.remove();
      } catch (e) {}
    }
  }

  _showCrossIconWidget() {
    return (widget.textEditingController.text.isNotEmpty);
  }

  _showSnackBar(String errorData) {
    if(widget.showError && mounted){
      final snackBar = SnackBar(
        content: Text("$errorData"),
      );

      // Find the ScaffoldMessenger in the widget tree
      // and use it to show a SnackBar.
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    }

  }
}

PlacesAutocompleteResponse parseResponse(Map responseBody) {
  return PlacesAutocompleteResponse.fromJson(
      responseBody as Map<String, dynamic>);
}

PlaceDetails parsePlaceDetailMap(Map responseBody) {
  return PlaceDetails.fromJson(responseBody as Map<String, dynamic>);
}

typedef ItemClick = void Function(Prediction postalCodeResponse);
typedef GetPlaceDetailswWithLatLng = void Function(
    Prediction postalCodeResponse);

typedef ListItemBuilder = Widget Function(
    BuildContext context, int index, Prediction prediction);
