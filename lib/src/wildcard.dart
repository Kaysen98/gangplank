class LCUWildcard {
  bool match(String target, String query) {
    if (!query.contains('*')) {
      // QUERY DOES NOT CONTAIN WILDCARDS -> EQUALS CHECK

      return target == query;
    }

    // SPLIT QUERY BY WILDCARDS

    final splitMatchStr = query.split('*');

    // REMOVE WILDCARDS IN THE BEGINNING AND END

    splitMatchStr.removeWhere((part) => part.isEmpty);

    if (!query.startsWith('*')) {
      // DOES NOT START WITH WILDCARD -> EXECUTE STARTS WITH

      if (target.startsWith(splitMatchStr[0])) {
        // ENDPOINT STARTS WITH THE FIRST OCCURRENCE IN ARRAY -> DO NOTHING
      } else {
        // ENDPOINT DOES NOT START WITH THE FIRST OCCURENCE IN ARRAY

        return false;
      }
    }

    if (!query.endsWith('*')) {
      // DOES NOT END WITH WILDCARD -> EXECUTE ENDS WITH

      if (target.endsWith(splitMatchStr[splitMatchStr.length - 1])) {
        // ENDPOINT ENDS WITH THE LAST OCCURRENCE IN ARRAY -> DO NOTHING
      } else {
        // ENDPOINT DOES NOT END WITH THE LAST OCCURRENCE IN ARRAY

        return false;
      }
    }

    for (String part in splitMatchStr) {
      int indexOfMatch = target.indexOf(part);

      if (indexOfMatch == -1) {
        // PART COULD NOT BE FOUND IN TARGET

        return false;
      }

      target = target.replaceRange(indexOfMatch, indexOfMatch + part.length, '');
    }

    return true;
  }
}
