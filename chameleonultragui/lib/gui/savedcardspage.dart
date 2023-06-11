import 'package:flutter/material.dart';

class SavedCardsPage extends StatelessWidget {
  /* Todo list:
  create dynamic list from database.
  2 columns. 1 for description, one for UID?
  Write key to slot upon clicking
  Maybe add Import and Export buttons so one can Im and Export .bin dumps
  */
  const SavedCardsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Saved Cards'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, // Center
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: () {
                      // Import card or cards from file
                    },
                    icon: const Icon(Icons.download_rounded),
                  ),
                  IconButton(
                    onPressed: () {
                      // Export card or cards to file
                    }, 
                    icon: const Icon(Icons.upload_rounded),
                  ),
                ],
              ),
            ),
            const Row(
              children: [
                Text("Device: ", style: TextStyle(fontSize: 20),),
              ],
            ),
            Expanded(
              child: GridView(
                padding: const EdgeInsets.all(20),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 3.5,
                ),
                scrollDirection: Axis.vertical,
                children: [
                  ElevatedButton(
                    onPressed: () {},
                    style: ButtonStyle(
                      shape:
                        MaterialStateProperty.all<RoundedRectangleBorder>(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18.0),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.nfc_rounded, color: Colors.red,),
                          ],
                        ),
                        Expanded(
                          flex: 1,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Column(
                                children: [
                                  Text("Apartment", style: TextStyle(fontSize: MediaQuery.of(context).size.width / 40)),
                                  Text("MFC 1k", style: TextStyle(fontSize: MediaQuery.of(context).size.width / 40)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {},
                    style: ButtonStyle(
                      shape:
                        MaterialStateProperty.all<RoundedRectangleBorder>(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18.0),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.nfc_rounded, color: Colors.blue,),
                          ],
                        ),
                        Expanded(
                          flex: 1,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Column(
                                children: [
                                  Text("Shop", style: TextStyle(fontSize: MediaQuery.of(context).size.width / 40)),
                                  Text("MDES 4k", style: TextStyle(fontSize: MediaQuery.of(context).size.width / 40)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {},
                    style: ButtonStyle(
                      shape:
                        MaterialStateProperty.all<RoundedRectangleBorder>(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18.0),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.nfc_rounded, color: Colors.green,),
                          ],
                        ),
                        Expanded(
                          flex: 1,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Column(
                                children: [
                                  Text("Unused", style: TextStyle(fontSize: MediaQuery.of(context).size.width / 40)),
                                  Text("None", style: TextStyle(fontSize: MediaQuery.of(context).size.width / 40)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {},
                    style: ButtonStyle(
                      shape:
                        MaterialStateProperty.all<RoundedRectangleBorder>(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18.0),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.nfc_rounded, color: Colors.purple,),
                          ],
                        ),
                        Expanded(
                          flex: 1,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Column(
                                children: [
                                  Text("Alarm", style: TextStyle(fontSize: MediaQuery.of(context).size.width / 40)),
                                  Text("T55xx", style: TextStyle(fontSize: MediaQuery.of(context).size.width / 40)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {},
                    style: ButtonStyle(
                      shape:
                        MaterialStateProperty.all<RoundedRectangleBorder>(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18.0),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.nfc_rounded, color: Colors.lime,),
                          ],
                        ),
                        Expanded(
                          flex: 1,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Column(
                                children: [
                                  Text("Unused", style: TextStyle(fontSize: MediaQuery.of(context).size.width / 40)),
                                  Text("None", style: TextStyle(fontSize: MediaQuery.of(context).size.width / 40)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {},
                    style: ButtonStyle(
                      shape:
                        MaterialStateProperty.all<RoundedRectangleBorder>(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18.0),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.nfc_rounded, color: Colors.black,),
                          ],
                        ),
                        Expanded(
                          flex: 1,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Column(
                                children: [
                                  Text("Unnamed", style: TextStyle(fontSize: MediaQuery.of(context).size.width / 40)),
                                  Text("MFC 1k", style: TextStyle(fontSize: MediaQuery.of(context).size.width / 40)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {},
                    style: ButtonStyle(
                      shape:
                        MaterialStateProperty.all<RoundedRectangleBorder>(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18.0),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.nfc_rounded, color: Colors.grey,),
                          ],
                        ),
                        Expanded(
                          flex: 1,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Column(
                                children: [
                                  Text("Work", style: TextStyle(fontSize: MediaQuery.of(context).size.width / 40)),
                                  Text("MDES 1k", style: TextStyle(fontSize: MediaQuery.of(context).size.width / 40)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {},
                    style: ButtonStyle(
                      shape:
                        MaterialStateProperty.all<RoundedRectangleBorder>(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18.0),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.nfc_rounded, color: Colors.indigo,),
                          ],
                        ),
                        Expanded(
                          flex: 1,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Column(
                                children: [
                                  Text("Unused", style: TextStyle(fontSize: MediaQuery.of(context).size.width / 40)),
                                  Text("Free", style: TextStyle(fontSize: MediaQuery.of(context).size.width / 40)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                const Text("Locally saved cards: ", style: TextStyle(fontSize: 20),),
                IconButton(
                  onPressed: () {
                    // Sync cards / Download device cards to local storage
                  }, 
                  icon: const Icon(Icons.sync_rounded),
                ),
              ],
            ),
            Expanded(
              child: GridView(
                padding: const EdgeInsets.all(20),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 3.5,
                ),
                scrollDirection: Axis.vertical,
                children: [
                  ElevatedButton(
                    onPressed: () {},
                    style: ButtonStyle(
                      shape:
                        MaterialStateProperty.all<RoundedRectangleBorder>(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18.0),
                        ),
                      ),
                    ),
                    child: const Icon(Icons.add),
                  ),
                  ElevatedButton(
                    onPressed: () {},
                    style: ButtonStyle(
                      shape:
                        MaterialStateProperty.all<RoundedRectangleBorder>(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18.0),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.nfc_rounded, color: Colors.red,),
                          ],
                        ),
                        Expanded(
                          flex: 1,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Column(
                                children: [
                                  Text("Testcard", style: TextStyle(fontSize: MediaQuery.of(context).size.width / 40)),
                                  Text("MFC 1k", style: TextStyle(fontSize: MediaQuery.of(context).size.width / 40)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ]
              ),
            ),
            const Row(
              children: [
                Text("Locally saved keys: ", style: TextStyle(fontSize: 20),)
              ],
            ),
            Expanded(
              child: GridView(
                padding: const EdgeInsets.all(20),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 3.5,
                ),
                scrollDirection: Axis.vertical,
                children: [
                  ElevatedButton(
                    onPressed: () {},
                    style: ButtonStyle(
                      shape:
                        MaterialStateProperty.all<RoundedRectangleBorder>(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18.0),
                        ),
                      ),
                    ),
                    child: const Icon(Icons.add),
                  ),
                  ElevatedButton(
                    onPressed: () {},
                    style: ButtonStyle(
                      shape:
                        MaterialStateProperty.all<RoundedRectangleBorder>(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18.0),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: [
                            Icon(Icons.key_rounded, color: Colors.blue,),
                          ],
                        ),
                        Expanded(
                          flex: 1,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Column(
                                children: [
                                  Text("Wifi Card Key", style: TextStyle(fontSize: MediaQuery.of(context).size.width / 40)),
                                  Text("0x2353as87", style: TextStyle(fontSize: MediaQuery.of(context).size.width / 40)),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ]
              ),
            ),
          ],
        ),
      ),
    );
  }
}
