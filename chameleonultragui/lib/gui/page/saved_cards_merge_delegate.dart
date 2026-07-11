part of 'saved_cards.dart';

class DictMergeDelegate extends SearchDelegate<String> {
  final List<Dictionary> dicts;
  final Dictionary mergeDict;
  List<bool> selectedDicts = [];

  DictMergeDelegate(this.dicts, this.mergeDict) {
    selectedDicts = List.filled(dicts.length, false);
  }

  @override
  List<Widget> buildActions(BuildContext context) {
    var appState = context.read<ChameleonGUIState>();
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
      const SizedBox(width: 10),
      IconButton(
        icon: const Icon(Icons.merge),
        onPressed: () {
          List<Dictionary> selectedForMerge = [];
          List<Dictionary> output = dicts;

          // Get selected dicts
          for (var i = 0; i < selectedDicts.length; i++) {
            if (selectedDicts[i]) {
              selectedForMerge.add(dicts[i]);
            }
          }

          // Merge
          for (var dict in selectedForMerge) {
            mergeDict.keys = mergeDict.keys + dict.keys;
          }

          // Deduplicate
          mergeDict.keys = <int, Uint8List>{
            for (var key in mergeDict.keys) Object.hashAll(key): key
          }.values.toList();

          // Replace
          for (var i = 0; i < output.length; i++) {
            if (output[i].id == mergeDict.id) {
              output[i] = mergeDict;
            }
          }

          appState.sharedPreferencesProvider.setDictionaries(output);

          Navigator.pop(context);
          appState.changesMade();
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
    final results = dicts
        .where((dict) => dict.name.toLowerCase().contains(query.toLowerCase()));
    var localizations = AppLocalizations.of(context)!;

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (BuildContext context, int index) {
        final dict = results.elementAt(index);
        if (dict.id == mergeDict.id) {
          return Container();
        }
        return CheckboxListTile(
          value: selectedDicts[index],
          title: Text(dict.name),
          secondary: Icon(Icons.key, color: dict.color),
          subtitle: Text(
              "${dict.keys.length.toString()} ${localizations.total_keys.toLowerCase()}"),
          onChanged: (value) {},
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final results = dicts
        .where((dict) => dict.name.toLowerCase().contains(query.toLowerCase()));
    var localizations = AppLocalizations.of(context)!;

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (BuildContext context, int index) {
        final dict = results.elementAt(index);
        var appState = context.read<ChameleonGUIState>();
        if (dict.id == mergeDict.id) {
          return Container();
        }
        return CheckboxListTile(
          value: selectedDicts[index],
          title: Text(dict.name),
          secondary: Icon(Icons.key, color: dict.color),
          subtitle: Text(
              "${dict.keys.length.toString()} ${localizations.total_keys.toLowerCase()}"),
          onChanged: (value) {
            selectedDicts[index] = value!;
            appState.changesMade();
          },
        );
      },
    );
  }
}
