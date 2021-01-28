import 'package:expandable/expandable.dart';
import 'package:flutter/material.dart';
import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';
import 'package:torn_pda/models/travel/foreign_stock_in.dart';
import 'package:torn_pda/models/items_model.dart';
import 'package:torn_pda/models/inventory_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:torn_pda/providers/theme_provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:torn_pda/utils/travel/travel_times.dart';
import "dart:collection";
import 'dart:ui';

class ForeignStockCard extends StatefulWidget {
  final ForeignStock foreignStock;
  final bool inventoryEnabled;
  final InventoryModel inventoryModel;
  final ItemsModel allTornItems;
  final int capacity;
  final int moneyOnHand;
  final Function flagPressedCallback;

  ForeignStockCard(
      {@required this.foreignStock,
      @required this.inventoryEnabled,
      @required this.inventoryModel,
      @required this.capacity,
      @required this.allTornItems,
      @required this.moneyOnHand,
      @required this.flagPressedCallback,
      @required Key key})
      : super(key: key);

  @override
  _ForeignStockCardState createState() => _ForeignStockCardState();
}



class _ForeignStockCardState extends State<ForeignStockCard> {
  FirebaseFirestore _firestore = FirebaseFirestore.instance;

  var _expandableController = ExpandableController();

  Future _footerInformationRetrieved;
  bool _footerSuccessful = false;

  var _periodicMap = SplayTreeMap();

  var _averageTimeToRestock = 0;
  var _restockReliability = 0;
  var _projectedRestockDateTime = DateTime.now();
  var _depletionTrendPerSecond = 0.0;

  ThemeProvider _themeProvider;

  List<Color> gradientColors = [
    const Color(0xff23b6e6),
    const Color(0xff02d39a),
  ];

  @override
  void initState() {
    super.initState();
    _expandableController.addListener(() {
      if (_expandableController.expanded == true && !_footerSuccessful) {
        _footerInformationRetrieved = _getFooterInformation();
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
    _expandableController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _themeProvider = Provider.of<ThemeProvider>(context, listen: true);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ExpandablePanel(
          controller: _expandableController,
          theme: ExpandableThemeData(
            hasIcon: false,
          ),
          header: _header(),
          expanded: _footer(),
        ),
      ),
    );
  }

  Widget _header() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _firstRow(widget.foreignStock),
                SizedBox(height: 10),
                _secondRow(widget.foreignStock),
              ],
            ),
            _countryFlagAndArrow(widget.foreignStock),
          ],
        ),
      ],
    );
  }

  Widget _footer() {
    // AVERAGE CALCULATION
    var average = "unknown";
    var reliability = "";
    var reliabilityColor = Colors.transparent;
    if (_averageTimeToRestock > 0) {
      average = _formatDuration(Duration(seconds: _averageTimeToRestock));
      if (_restockReliability < 33) {
        reliability = "low";
        reliabilityColor = Colors.red;
      } else if (_restockReliability >= 33 && _restockReliability < 66) {
        reliability = "medium";
        reliabilityColor = Colors.orangeAccent;
      } else {
        reliability = "high";
        reliabilityColor = Colors.green;
      }
    }

    // WHEN TO TRAVEL
    // TODO: reference global variable, not method
    var travelSeconds = TravelTimes.travelTime(widget.foreignStock);

    var whenToTravel = "";
    var arrivalTime = "";
    var depletesTime = "";
    Color whenToTravelColor = _themeProvider.mainText;

    bool delayDeparture = false;
    DateTime delayedDeparture;

    // Calculates when to leave, taking into account:
    //  - If there are items: arrive before depletion
    //  - If there are no items: arrive when restock happens
    //  - Does NOT take into account a restock that depletes quickly
    var earliestArrival = DateTime.now().add(Duration(seconds: travelSeconds));
    if (earliestArrival.isAfter(_projectedRestockDateTime)) {
      // Avoid dividing by 0 if we have no trend
      if (widget.foreignStock.quantity > 0 && _depletionTrendPerSecond > 0) {
        var secondsToDeplete =
            widget.foreignStock.quantity / _depletionTrendPerSecond;

        // If depleting very slowly (more than a day)
        if (secondsToDeplete > 86400) {
          whenToTravel = "Travel NOW";
          depletesTime = "Depletes in more than a day";
        }
        // If we won't arrive before depletion
        else {
          var depletionDateTime =
              DateTime.now().add(Duration(seconds: secondsToDeplete.round()));
          if (earliestArrival.isAfter(depletionDateTime)) {
            whenToTravel = "Caution, depletes at "
                "${DateFormat('HH:mm').format(depletionDateTime)}";
            whenToTravelColor = Colors.orangeAccent;
          }
          // If we arrive before depletion
          else {
            whenToTravel = "Travel NOW";
            depletesTime = "Depletes at "
                "${DateFormat('HH:mm').format(depletionDateTime)}";
          }
        }
      }
      // Item is either empty or is not depleting
      else {
        // This will avoid recommending to travel with empty empty with no known
        // average restock time
        if (widget.foreignStock.quantity > 0 || average != "unknown") {
          whenToTravel = "Travel NOW";
        }
      }
      arrivalTime = "You will be there at "
          "${DateFormat('HH:mm').format(earliestArrival)}";
    }
    // If we arrive before restock if we depart now
    else {
      var additionalWait =
          _projectedRestockDateTime.difference(earliestArrival).inSeconds;

      delayDeparture = true;
      delayedDeparture =
          DateTime.now().add(Duration(seconds: additionalWait));

      whenToTravel =
          "Travel at ${DateFormat('HH:mm').format(delayedDeparture)}";
      var delayedArrival =
          delayedDeparture.add(Duration(seconds: travelSeconds));
      arrivalTime = "You will be there at "
          "${DateFormat('HH:mm').format(delayedArrival)}";
    }

    return FutureBuilder(
        future: _footerInformationRetrieved,
        builder: (BuildContext context, AsyncSnapshot<dynamic> snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (_footerSuccessful) {
              return Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (whenToTravel.isNotEmpty)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    whenToTravel,
                                    style: TextStyle(
                                        fontSize: 12, color: whenToTravelColor),
                                  ),
                                  if (depletesTime.isNotEmpty)
                                    Text(
                                      depletesTime,
                                      style: TextStyle(
                                        fontSize: 12,
                                      ),
                                    )
                                  else
                                    SizedBox.shrink(),
                                  Text(
                                    arrivalTime,
                                    style: TextStyle(
                                      fontSize: 12,
                                    ),
                                  ),
                                  SizedBox(height: 15),
                                ],
                              )
                            else
                              SizedBox.shrink(),
                            Text(
                              "Average restock time: $average",
                              style: TextStyle(
                                fontSize: 12,
                              ),
                            ),
                            if (reliability.isNotEmpty)
                              Row(
                                children: [
                                  Text(
                                    "Reliability: ",
                                    style: TextStyle(
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    "$reliability",
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: reliabilityColor,
                                    ),
                                  ),
                                ],
                              )
                            else
                              SizedBox.shrink(),
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: 20),
                    SizedBox(
                      height: 200,
                      width: 600,
                      child: LineChart(_mainChartData()),
                    ),
                  ],
                ),
              );
            } else {
              return Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  "There is an issue contacting the server, "
                  "please try again later",
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              );
            }
          } else {
            return Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
                child: CircularProgressIndicator(),
              ),
            );
          }
        });
  }

  Row _firstRow(ForeignStock stock) {
    var invQuantity = 0;
    if (widget.inventoryEnabled) {
      for (var invItem in widget.inventoryModel.inventory) {
        if (invItem.id == stock.id) {
          invQuantity = invItem.quantity;
          break;
        }
      }
    }

    return Row(
      children: <Widget>[
        Image.asset('images/torn_items/small/${stock.id}_small.png'),
        Padding(
          padding: EdgeInsets.only(right: 10),
        ),
        Column(
          children: [
            SizedBox(
              width: 100,
              child: Text(stock.name),
            ),
            widget.inventoryEnabled
                ? SizedBox(
                    width: 100,
                    child: Text(
                      "(inv: x$invQuantity)",
                      style: TextStyle(fontSize: 11),
                    ),
                  )
                : SizedBox.shrink(),
          ],
        ),
        Padding(
          padding: EdgeInsets.only(right: 15),
        ),
        SizedBox(
          width: 55,
          child: Text(
            'x${stock.quantity}',
            style: TextStyle(
              color: stock.quantity > 0 ? Colors.green : Colors.red,
              fontWeight:
                  stock.quantity > 0 ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        _returnLastUpdated(stock.timestamp),
      ],
    );
  }

  Row _secondRow(ForeignStock stock) {
    // Currency configuration
    final costCurrency = new NumberFormat("#,##0", "en_US");

    // Item cost
    Widget costWidget;
    costWidget = Text(
      '\$${costCurrency.format(stock.cost)}',
      style: TextStyle(fontWeight: FontWeight.bold),
    );

    // Profit and profit per hour
    Widget profitWidget;
    Widget profitPerMinuteWidget;
    final profitColor = stock.value <= 0 ? Colors.red : Colors.green;

    String profitFormatted = calculateProfit(stock.value.abs());
    if (stock.value <= 0) {
      profitFormatted = '-\$$profitFormatted';
    } else {
      profitFormatted = '+\$$profitFormatted';
    }

    profitWidget = Text(
      profitFormatted,
      style: TextStyle(color: profitColor),
    );

    // Profit per hour
    String profitPerHourFormatted =
        calculateProfit((stock.profit * widget.capacity).abs());
    if (stock.profit <= 0) {
      profitPerHourFormatted = '-\$$profitPerHourFormatted';
    } else {
      profitPerHourFormatted = '+\$$profitPerHourFormatted';
    }

    profitPerMinuteWidget = Text(
      '($profitPerHourFormatted/hour)',
      style: TextStyle(color: profitColor),
    );

    return Row(
      children: <Widget>[
        costWidget,
        Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: profitWidget,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8.0),
          child: profitPerMinuteWidget,
        ),
      ],
    );
  }

  String calculateProfit(int moneyInput) {
    final profitCurrencyHigh = new NumberFormat("#,##0.0", "en_US");
    final costCurrencyLow = new NumberFormat("#,##0", "en_US");
    String profitFormat;

    // Money standards to reduce string length (adding two zeros for .00)
    final billion = 1000000000;
    final million = 1000000;
    final thousand = 1000;

    // Profit
    if (moneyInput < -billion || moneyInput > billion) {
      final profitBillion = moneyInput / billion;
      profitFormat = '${profitCurrencyHigh.format(profitBillion)}B';
    } else if (moneyInput < -million || moneyInput > million) {
      final profitMillion = moneyInput / million;
      profitFormat = '${profitCurrencyHigh.format(profitMillion)}M';
    } else if (moneyInput < -thousand || moneyInput > thousand) {
      final profitThousand = moneyInput / thousand;
      profitFormat = '${profitCurrencyHigh.format(profitThousand)}K';
    } else {
      profitFormat = '${costCurrencyLow.format(moneyInput)}';
    }
    return profitFormat;
  }

  Widget _countryFlagAndArrow(ForeignStock stock) {
    String countryCode;
    String flag;
    switch (stock.country) {
      case CountryName.JAPAN:
        countryCode = 'JPN';
        flag = 'images/flags/stock/japan.png';
        break;
      case CountryName.HAWAII:
        countryCode = 'HAW';
        flag = 'images/flags/stock/hawaii.png';
        break;
      case CountryName.CHINA:
        countryCode = 'CHN';
        flag = 'images/flags/stock/china.png';
        break;
      case CountryName.ARGENTINA:
        countryCode = 'ARG';
        flag = 'images/flags/stock/argentina.png';
        break;
      case CountryName.UNITED_KINGDOM:
        countryCode = 'UK';
        flag = 'images/flags/stock/uk.png';
        break;
      case CountryName.CAYMAN_ISLANDS:
        countryCode = 'CAY';
        flag = 'images/flags/stock/cayman.png';
        break;
      case CountryName.SOUTH_AFRICA:
        countryCode = 'AFR';
        flag = 'images/flags/stock/south-africa.png';
        break;
      case CountryName.SWITZERLAND:
        countryCode = 'SWI';
        flag = 'images/flags/stock/switzerland.png';
        break;
      case CountryName.MEXICO:
        countryCode = 'MEX';
        flag = 'images/flags/stock/mexico.png';
        break;
      case CountryName.UAE:
        countryCode = 'UAE';
        flag = 'images/flags/stock/uae.png';
        break;
      case CountryName.CANADA:
        countryCode = 'CAN';
        flag = 'images/flags/stock/canada.png';
        break;
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        GestureDetector(
          child: Text(countryCode),
          onLongPress: () {
            _launchMoneyWarning(stock);
            widget.flagPressedCallback(true, false);
          },
          onTap: () {
            _launchMoneyWarning(stock);
            widget.flagPressedCallback(true, true);
          },
        ),
        Image.asset(
          flag,
          width: 30,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Icon(Icons.keyboard_arrow_down_outlined),
        ),
      ],
    );
  }

  void _launchMoneyWarning(ForeignStock stock) {
    // Currency configuration
    final costCurrency = new NumberFormat("#,##0", "en_US");

    var moneyOnHand = widget.moneyOnHand;
    String moneyToBuy = '';
    Color moneyToBuyColor = Colors.grey;
    if (moneyOnHand >= stock.cost * widget.capacity) {
      moneyToBuy =
          'You HAVE the \$${costCurrency.format(stock.cost * widget.capacity)} necessary to '
          'buy $widget.capacity ${stock.name}';
      moneyToBuyColor = Colors.green;
    } else {
      moneyToBuy =
          'You DO NOT HAVE the \$${costCurrency.format(stock.cost * widget.capacity)} '
          'necessary to buy $widget.capacity ${stock.name}. Add another '
          '\$${costCurrency.format((stock.cost * widget.capacity) - moneyOnHand)}';
      moneyToBuyColor = Colors.red;
    }

    BotToast.showText(
      text: moneyToBuy,
      textStyle: TextStyle(
        fontSize: 14,
        color: Colors.white,
      ),
      contentColor: moneyToBuyColor,
      duration: Duration(seconds: 6),
      contentPadding: EdgeInsets.all(10),
    );
  }

  Row _returnLastUpdated(int timeStamp) {
    var inputTime = DateTime.fromMillisecondsSinceEpoch(timeStamp * 1000);
    var timeDifference = DateTime.now().difference(inputTime);
    var timeString;
    var color;
    if (timeDifference.inMinutes < 1) {
      timeString = 'now';
      color = Colors.green;
    } else if (timeDifference.inMinutes == 1 && timeDifference.inHours < 1) {
      timeString = '1 min';
      color = Colors.green;
    } else if (timeDifference.inMinutes > 1 && timeDifference.inHours < 1) {
      timeString = '${timeDifference.inMinutes} min';
      color = Colors.green;
    } else if (timeDifference.inHours == 1 && timeDifference.inDays < 1) {
      timeString = '1 hour';
      color = Colors.orange;
    } else if (timeDifference.inHours > 1 && timeDifference.inDays < 1) {
      timeString = '${timeDifference.inHours} hours';
      color = Colors.red;
    } else if (timeDifference.inDays == 1) {
      timeString = '1 day';
      color = Colors.green;
    } else {
      timeString = '${timeDifference.inDays} days';
      color = Colors.green;
    }
    return Row(
      children: <Widget>[
        Icon(
          Icons.access_time,
          size: 14,
          color: color,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 5),
          child: Text(
            timeString,
            style: TextStyle(color: color),
          ),
        ),
      ],
    );
  }

  Future _getFooterInformation() async {
    // Build code name
    var codeName = "${widget.foreignStock.countryCode}-"
        "${widget.foreignStock.name}";

    try {
      // Get the stock
      var firestoreData =
          await _firestore.collection("stocks-main").doc(codeName).get();

      // Chart date
      var firestoreMap = firestoreData
          .data()['periodicMap']
          .map((k, v) => MapEntry(int.parse(k), v));

      _periodicMap =
          SplayTreeMap<int, int>.from(firestoreMap, (a, b) => a.compareTo(b));

      // RESTOCK AVERAGE AND RELIABILITY
      List restock = firestoreData.data()['restockElapsed'].toList();
      if (restock.length > 0) {
        var sum = 0;
        for (var res in restock) sum += res;
        _averageTimeToRestock = sum ~/ restock.length;

        var twentyPercent = _averageTimeToRestock * 0.2;
        var insideTenPercentAverage = 0;
        for (var res in restock) {
          if ((_averageTimeToRestock + twentyPercent > res) &&
              (_averageTimeToRestock - twentyPercent < res)) {
            insideTenPercentAverage++;
          }
        }
        // We need a minimum number of restocks to give credibility
        // TODO: change to 5
        if (restock.length > 2) {
          _restockReliability = insideTenPercentAverage * 100 ~/ restock.length;
        } else {
          _restockReliability = 0;
        }
      }

      // TIMES TO RESTOCK
      var lastEmpty = firestoreData.data()['lastEmpty'];
      var lastEmptyDateTime =
          DateTime.fromMillisecondsSinceEpoch(lastEmpty * 1000);
      _projectedRestockDateTime =
          lastEmptyDateTime.add(Duration(seconds: _averageTimeToRestock));

      // CURRENT DEPLETION TREND
      if (widget.foreignStock.quantity > 0) {
        var inverseList = [];
        var inverseMap =
            SplayTreeMap<int, int>.from(firestoreMap, (a, b) => b.compareTo(a));
        inverseMap.entries
            .forEach((e) => inverseList.add("${e.key}, ${e.value}"));
        var currentTimestamp = int.parse((inverseList[0].split(","))[0]);
        var currentQuantity = int.parse((inverseList[0].split(","))[1]);
        var fullTimestamp = 0;
        var fullQuantity = 0;
        // We look from now until the last full quantity (list comes from reversed map)
        for (var i = 0; i < inverseList.length; i++) {
          var qty = int.parse((inverseList[i].split(","))[1]);
          var ts = int.parse((inverseList[i].split(","))[0]);
          if (qty == 0) break;
          fullQuantity = qty;
          fullTimestamp = ts;
        }
        var quantityVariation = fullQuantity - currentQuantity;
        var secondsInVariation = currentTimestamp - fullTimestamp;

        var ratio = quantityVariation / secondsInVariation;
        if (ratio > 0) {
          _depletionTrendPerSecond = ratio;
        }
      }

      setState(() {
        _footerSuccessful = true;
      });
    } catch (e) {
      setState(() {
        _footerSuccessful = false;
      });
    }
  }

  LineChartData _mainChartData() {
    var spots = <FlSpot>[];
    double count = 0;
    double maxY = 0;
    var timestamps = <int>[];

    _periodicMap.forEach((key, value) {
      spots.add(FlSpot(count, value.toDouble()));
      timestamps.add(key);
      if (value > maxY) maxY = value.toDouble();
      count++;
    });

    double interval;
    if (maxY > 1000) {
      interval = 1000;
    } else if (maxY > 200 && maxY <= 1000) {
      interval = 200;
    } else if (maxY > 20 && maxY <= 200) {
      interval = 20;
    } else {
      interval = 2;
    }

    return LineChartData(
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
            fitInsideHorizontally: true,
            fitInsideVertically: false,
            tooltipBgColor: Colors.blueGrey.withOpacity(1),
            getTooltipItems: (value) {
              var tooltips = <LineTooltipItem>[];
              for (var spot in value) {
                // Get time
                var ts = 0;
                var timesList = [];
                _periodicMap.entries.forEach((e) => timesList.add("${e.key}"));
                var x = spot.x.toInt();
                if (x > timesList.length) {
                  x = timesList.length;
                }
                ts = int.parse(timesList[x]);
                var date = DateTime.fromMillisecondsSinceEpoch(ts * 1000);

                LineTooltipItem thisItem = LineTooltipItem(
                  "${spot.y.toInt()} items"
                  "\nat ${DateFormat('HH:mm').format(date)}",
                  TextStyle(
                    fontSize: 12,
                  ),
                );
                tooltips.add(thisItem);
              }

              return tooltips;
            }),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: const Color(0xff37434d),
            strokeWidth: 0.4,
          );
        },
      ),
      titlesData: FlTitlesData(
        show: true,
        bottomTitles: SideTitles(
          rotateAngle: -60,
          showTitles: true,
          interval: _periodicMap.length > 12 ? _periodicMap.length / 12 : null,
          reservedSize: 20,
          margin: 20,
          getTextStyles: (xValue) {
            if (xValue.toInt() >= _periodicMap.length) {
              xValue = xValue - 1;
            }
            var date = DateTime.fromMillisecondsSinceEpoch(
                timestamps[xValue.toInt()] * 1000);
            var difference = DateTime.now().difference(date).inHours;

            Color myColor = Colors.transparent;
            if (difference < 24) {
              myColor = Colors.green;
            } else {
              myColor = Colors.blue;
            }
            return TextStyle(
              color: myColor,
              fontSize: 10,
            );
          },
          getTitles: (xValue) {
            if (xValue.toInt() >= _periodicMap.length) {
              xValue = xValue - 1;
            }
            var date = DateTime.fromMillisecondsSinceEpoch(
                timestamps[xValue.toInt()] * 1000);
            return DateFormat('HH:mm').format(date);
          },
        ),
        leftTitles: SideTitles(
          showTitles: true,
          interval: interval,
          reservedSize: 10,
          margin: 12,
          getTextStyles: (value) => const TextStyle(
            color: Color(0xff67727d),
            fontSize: 10,
          ),
          getTitles: (yValue) {
            if (maxY > 1000) {
              return "${(yValue / 1000).truncate().toStringAsFixed(0)}K";
            }
            return yValue.floor().toString();
          },
        ),
      ),
      borderData: FlBorderData(
          show: true,
          border: Border.all(color: const Color(0xff37434d), width: 1)),
      minX: 0,
      maxX: _periodicMap.length.toDouble(),
      minY: 0,
      maxY: maxY + maxY * 0.1,
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: false,
          colors: gradientColors,
          barWidth: 1.5,
          isStrokeCapRound: true,
          dotData: FlDotData(
            show: false,
          ),
          belowBarData: BarAreaData(
            show: true,
            colors:
                gradientColors.map((color) => color.withOpacity(0.3)).toList(),
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    return "${twoDigits(duration.inHours)}h ${twoDigitMinutes}m";
  }

  
}
