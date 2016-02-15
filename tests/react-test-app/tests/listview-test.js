/* Copyright 2016 Realm Inc - All Rights Reserved
 * Proprietary and Confidential
 */

'use strict';

const Realm = require('realm');
const { ListView } = require('realm/react-native');
const { assertEqual, assertTrue } = require('realm-tests/asserts');

const OBJECT_SCHEMA = {
    name: 'UniqueObject',
    primaryKey: 'id',
    properties: {
        id: 'int',
    }
};

function createRealm() {
    let realm = new Realm({schema: [OBJECT_SCHEMA]});

    realm.write(() => {
        for (let i = 0; i < 100; i++) {
            realm.create('UniqueObject', {id: i});
        }
    });

    return realm;
}

function createDataSource() {
    return new ListView.DataSource({
        rowHasChanged: (a, b) => a.id !== b.id,
    });
}

module.exports = {
    afterEach() {
        Realm.clearTestState();
    },

    testDataSource() {
        let realm = createRealm();
        let objects = realm.objects('UniqueObject');
        objects.sortByProperty('id');

        let dataSource = createDataSource().cloneWithRows(objects);
        let count = objects.length;

        // Make sure the section header should update.
        assertTrue(dataSource.sectionHeaderShouldUpdate(0));

        // All rows should need to update.
        for (let i = 0; i < count; i++) {
            assertTrue(dataSource.rowShouldUpdate(0, i));
        }

        // Clone data source with no changes and make sure no rows need to update.
        dataSource = dataSource.cloneWithRows(objects);
        for (let i = 0; i < count; i++) {
            assertTrue(!dataSource.rowShouldUpdate(0, i));
        }

        // Delete the second object and make sure current data source is unchanged.
        realm.write(() => realm.delete(objects[1]));
        for (let i = 0; i < count; i++) {
            assertTrue(!dataSource.rowShouldUpdate(0, i));
        }

        // Getting the row data for the second row should return null.
        assertEqual(dataSource.getRow('s1', 1), null);

        // Clone data source and make sure all rows after the first one need to update.
        dataSource = dataSource.cloneWithRows(objects);
        for (let i = 0; i < count - 1; i++) {
            let changed = dataSource.rowShouldUpdate(0, i);
            assertTrue(i == 0 ? !changed : changed);
        }

        // Create an object at the ened and make sure only the last row needs to update.
        realm.write(() => realm.create('UniqueObject', {id: count}));
        dataSource = dataSource.cloneWithRows(objects);
        for (let i = 0; i < count; i++) {
            let changed = dataSource.rowShouldUpdate(0, i);
            assertTrue(i < count - 1 ? !changed : changed);
        }
    },
};
