// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:get/get.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:provider/provider.dart';
import 'package:torn_pda/models/stakeouts/stakeout_model.dart';
import 'package:torn_pda/providers/chain_status_provider.dart';
import 'package:torn_pda/providers/stakeouts_controller.dart';
import 'package:torn_pda/providers/webview_provider.dart';
import 'package:url_launcher/url_launcher.dart';

// Project imports:
import 'package:torn_pda/providers/settings_provider.dart';
import 'package:torn_pda/providers/theme_provider.dart';
import 'package:torn_pda/providers/user_details_provider.dart';

class StakeoutCard extends StatefulWidget {
  final Stakeout stakeout;

  // Key is needed to update at least the hospital counter individually
  StakeoutCard({
    @required this.stakeout,
    @required Key key,
  }) : super(key: key);

  @override
  _StakeoutCardState createState() => _StakeoutCardState();
}

class _StakeoutCardState extends State<StakeoutCard> {
  ThemeProvider _themeProvider;
  SettingsProvider _settingsProvider;
  UserDetailsProvider _userProvider;
  ChainStatusProvider _chainProvider;
  WebViewProvider _webViewProvider;

  Stakeout _stakeout;
  final StakeoutsController _s = Get.put(StakeoutsController());

  String _currentLifeString = "";
  String _lastUpdatedString;
  int _lastUpdatedMinutes;

  @override
  void initState() {
    super.initState();
    _stakeout = widget.stakeout;
    _webViewProvider = context.read<WebViewProvider>();
    _settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    _userProvider = Provider.of<UserDetailsProvider>(context, listen: false);
    _chainProvider = Provider.of<ChainStatusProvider>(context, listen: false);
  }

  @override
  Widget build(BuildContext context) {
    _themeProvider = Provider.of<ThemeProvider>(context, listen: true);
    return Slidable(
      startActionPane: ActionPane(
        motion: const ScrollMotion(),
        extentRatio: 0.5,
        children: [
          SlidableAction(
            label: 'Hide',
            backgroundColor: Colors.blue,
            icon: Icons.delete,
            onPressed: (context) {
              _s.removeStakeout(removeId: _stakeout.id);
            },
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0),
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4.0)),
          elevation: 2,
          child: ClipPath(
            clipper: ShapeBorderClipper(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // LINE 1
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(12, 5, 10, 0),
                  child: Row(
                    children: <Widget>[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          GestureDetector(
                            child: Row(
                              children: [
                                Icon(MdiIcons.cctv),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 5),
                                ),
                                SizedBox(
                                  width: 95,
                                  child: Text(
                                    '${_stakeout.name}',
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            onTap: () {
                              _openBrowser();
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // LINE 4
                Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(8, 5, 15, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Row(
                          children: <Widget>[
                            SizedBox(
                              width: 30,
                              height: 20,
                              child: IconButton(
                                padding: EdgeInsets.all(0),
                                iconSize: 20,
                                icon: Icon(
                                  MdiIcons.notebookEditOutline,
                                  size: 18,
                                ),
                                onPressed: () {
                                  _showNotesDialog();
                                },
                              ),
                            ),
                            SizedBox(width: 5),
                            Text(
                              'Notes: ',
                              style: TextStyle(fontSize: 12),
                            ),
                            Flexible(
                              child: Text(
                                '${_stakeout.personalNote}',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showNotesDialog() {
    // TODO
    /*
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0.0,
          backgroundColor: Colors.transparent,
          content: SingleChildScrollView(
            child: PersonalNotesDialog(
              memberModel: _stakeout,
              noteType: PersonalNoteType.factionMember,
            ),
          ),
        );
      },
    );
    */
  }

  void _openBrowser() async {
    var browserType = _settingsProvider.currentBrowser;
    String url = 'https://www.torn.com/loader.php?sid=attack&user2ID=${_stakeout.id}';
    switch (browserType) {
      case BrowserSetting.app:
        await _webViewProvider.openBrowserPreference(
          context: context,
          useDialog: _settingsProvider.useQuickBrowser,
          url: url,
        );
        break;
      case BrowserSetting.external:
        if (await canLaunchUrl(Uri.parse(url))) {
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        }
        break;
    }
  }
}
