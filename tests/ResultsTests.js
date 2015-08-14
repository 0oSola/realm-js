////////////////////////////////////////////////////////////////////////////
//
// Copyright 2015 Realm Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
////////////////////////////////////////////////////////////////////////////

'use strict';

var ResultsTests = {
    testResultsLength: function() {
        var realm = new Realm({schema: [TestObjectSchema]});
        var objects = realm.objects('TestObject');
        TestCase.assertEqual(objects.length, 0);

        realm.write(function() {
            realm.create('TestObject', [1]);
            TestCase.assertEqual(objects.length, 1);
        });
        TestCase.assertEqual(objects.length, 1);
    },
    testResultsSubscript: function() {
        var realm = new Realm({schema: [PersonObject]});
        realm.write(function() {
            realm.create('PersonObject', ['name1', 1]);
            realm.create('PersonObject', ['name2', 2]);
        });

        var people = realm.objects('PersonObject');
        TestCase.assertEqual(people[0].age, 1);
        TestCase.assertEqual(people[1].age, 2);
        TestCase.assertThrows(function() { people[2]; }, 'Invalid index');
        TestCase.assertThrows(function() { people[-1]; }, 'Invalid index');
        TestCase.assertTrue(Object.getPrototypeOf(people[0]) === PersonObject.prototype);
    },
    testResultsInvalidProperty: function() {
        var realm = new Realm({schema: [TestObjectSchema]});
        var objects = realm.objects('TestObject');
        TestCase.assertEqual(undefined, objects.ablasdf);
    },
    testResultsEnumberate: function() {
        var realm = new Realm({schema: [TestObjectSchema]});
        var objects = realm.objects('TestObject');
        for (var object in objects) {
            TestCase.assertTrue(false, "No objects should have been enumerated");
        }

        realm.write(function() {
            realm.create('TestObject', [1]);
            TestCase.assertEqual(objects.length, 1);
        });

        var count = 0;
        for (var object in objects) {
            count++;
            //TestCase.assertTrue(object instanceof Object);
        }    
        TestCase.assertEqual(1, count);
    },
}
