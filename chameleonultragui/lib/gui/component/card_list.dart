import 'package:chameleonultragui/bridge/chameleon.dart';
import 'package:chameleonultragui/helpers/general.dart';
import 'package:chameleonultragui/helpers/mifare_classic/general.dart';
import 'package:chameleonultragui/sharedprefsprovider.dart';
import 'package:flutter/material.dart';

// Localizations
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

enum SearchFilter { all, hf, lf }

class CardSearchDelegate extends SearchDelegate<String> {
  final List<CardSave> cards;
  final int gridPosition;
  final dynamic onTap;
  SearchFilter filter = SearchFilter.all;

  CardSearchDelegate(this.cards, this.gridPosition, this.onTap);

  @override
  List<Widget> buildActions(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;
    return [
      StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return DropdownButton(
            items: [
              DropdownMenuItem(
                value: SearchFilter.all,
                child: Text(
                  localizations.all,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              DropdownMenuItem(
                value: SearchFilter.hf,
                child: Text(
                  localizations.hf,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              DropdownMenuItem(
                value: SearchFilter.lf,
                child: Text(
                  localizations.lf,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            onChanged: (SearchFilter? value) {
              if (value != null) {
                setState(() {
                  filter = value;
                });
              }
            },
            value: filter,
          );
        },
      ),
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, '');
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    final results = cards.where((card) =>
        (((card.name.toLowerCase().contains(query.toLowerCase())) ||
                (chameleonTagToString(card.tag)
                    .toLowerCase()
                    .contains(query.toLowerCase()))) &&
            ((filter == SearchFilter.all) ||
                (filter == SearchFilter.hf &&
                    chameleonTagToFrequency(card.tag) == TagFrequency.hf) ||
                (filter == SearchFilter.lf &&
                    chameleonTagToFrequency(card.tag) == TagFrequency.lf))));

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (BuildContext context, int index) {
        final card = results.elementAt(index);
        return Column(
          children: [
            ElevatedButton(
              onPressed: () {
                // Set card here
                Navigator.pop(context);
              },
              child: ListTile(
                leading: Icon(
                    (chameleonTagToFrequency(card.tag) == TagFrequency.hf)
                        ? Icons.credit_card
                        : Icons.wifi,
                    color: card.color),
                title: Text(
                  card.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  chameleonTagToString(card.tag),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final results = cards.where((card) =>
        (((card.name.toLowerCase().contains(query.toLowerCase())) ||
                (chameleonTagToString(card.tag)
                    .toLowerCase()
                    .contains(query.toLowerCase()))) &&
            ((filter == SearchFilter.all) ||
                (filter == SearchFilter.hf &&
                    chameleonTagToFrequency(card.tag) == TagFrequency.hf) ||
                (filter == SearchFilter.lf &&
                    chameleonTagToFrequency(card.tag) == TagFrequency.lf))));

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (BuildContext context, int index) {
        final card = results.elementAt(index);
        return ListTile(
          leading: Icon(
              (chameleonTagToFrequency(card.tag) == TagFrequency.hf)
                  ? Icons.credit_card
                  : Icons.wifi,
              color: card.color),
          title: Text(card.name),
          subtitle: Text(
            chameleonTagToString(card.tag) +
                ((chameleonTagSaveCheckForMifareClassicEV1(card))
                    ? " EV1"
                    : ""),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () async {
            onTap(card, gridPosition, close);
          },
        );
      },
    );
  }
}
