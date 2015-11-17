/* Copyright 2015 Realm Inc - All Rights Reserved
 * Proprietary and Confidential
 */

'use strict';

var Realm = require('realm');
var BaseTest = require('./base-test');
var TestCase = require('./asserts');
var schemas = require('./schemas');

// 31 random bytes (purposefully an odd number).
var RANDOM_DATA = new Uint8Array([
    0xd8, 0x21, 0xd6, 0xe8, 0x0c, 0x57, 0xbc, 0xb2, 0x6a, 0x15, 0x77, 0x30, 0xac, 0x77, 0x96, 0xd9,
    0x67, 0x1e, 0x40, 0xa7, 0x6d, 0x52, 0x83, 0xda, 0x07, 0x29, 0x9c, 0x70, 0x38, 0x48, 0x4e,
]);

module.exports = BaseTest.extend({
    testBasicTypesPropertyGetters: function() {
        var basicTypesValues = [true, 1, 1.1, 1.11, 'string', new Date(1), RANDOM_DATA];
        var realm = new Realm({schema: [schemas.BasicTypes]});
        var object;

        realm.write(function() {
            object = realm.create('BasicTypesObject', basicTypesValues);
        });

        for (var i = 0; i < schemas.BasicTypes.properties.length; i++) {
            var prop = schemas.BasicTypes.properties[i];
            if (prop.type == Realm.Types.FLOAT) {
                TestCase.assertEqualWithTolerance(object[prop.name], basicTypesValues[i], 0.000001);
            }
            else if (prop.type == Realm.Types.DATA) {
                TestCase.assertArraysEqual(new Uint8Array(object[prop.name]), RANDOM_DATA);
            }
            else if (prop.type == Realm.Types.DATE) {
                TestCase.assertEqual(object[prop.name].getTime(), basicTypesValues[i].getTime());
            }
            else {
                TestCase.assertEqual(object[prop.name], basicTypesValues[i]);
            }
        }

        TestCase.assertEqual(object.nonexistent, undefined);
    },
    testNullableBasicTypesPropertyGetters: function() {
        var nullValues = [null, null, null, null, null, null, null];
        var basicTypesValues = [true, 1, 1.1, 1.11, 'string', new Date(1), RANDOM_DATA];

        var realm = new Realm({schema: [schemas.NullableBasicTypes]});
        var nullObject = null;
        var object = null;
        realm.write(function() {
            nullObject = realm.create('NullableBasicTypesObject', nullValues);
            object = realm.create('NullableBasicTypesObject', basicTypesValues);
        });

        for (var i = 0; i < schemas.BasicTypes.properties.length; i++) {
            var prop = schemas.BasicTypes.properties[i];
            TestCase.assertEqual(nullObject[prop.name], null);

            if (prop.type == Realm.Types.FLOAT) {
                TestCase.assertEqualWithTolerance(object[prop.name], basicTypesValues[i], 0.000001);
            }
            else if (prop.type == Realm.Types.DATA) {
                TestCase.assertArraysEqual(new Uint8Array(object[prop.name]), RANDOM_DATA);
            }
            else if (prop.type == Realm.Types.DATE) {
                TestCase.assertEqual(object[prop.name].getTime(), basicTypesValues[i].getTime());
            }
            else {
                TestCase.assertEqual(object[prop.name], basicTypesValues[i]);
            }
        }

    },
    testBasicTypesPropertySetters: function() {
        var basicTypesValues = [true, 1, 1.1, 1.11, 'string', new Date(1), new ArrayBuffer()];
        var realm = new Realm({schema: [schemas.BasicTypes]});
        var obj = null;

        realm.write(function() {
            obj = realm.create('BasicTypesObject', basicTypesValues);
            obj.boolCol = false;
            obj.intCol = 2;
            obj.floatCol = 2.2;
            obj.doubleCol = 2.22;
            obj.stringCol = 'STRING';
            obj.dateCol = new Date(2);
            obj.dataCol = RANDOM_DATA;
        });

        TestCase.assertEqual(obj.boolCol, false, 'wrong bool value');
        TestCase.assertEqual(obj.intCol, 2, 'wrong int value');
        TestCase.assertEqualWithTolerance(obj.floatCol, 2.2, 0.000001, 'wrong float value');
        TestCase.assertEqual(obj.doubleCol, 2.22, 'wrong double value');
        TestCase.assertEqual(obj.stringCol, 'STRING', 'wrong string value');
        TestCase.assertEqual(obj.dateCol.getTime(), 2, 'wrong date value');
        TestCase.assertArraysEqual(new Uint8Array(obj.dataCol), RANDOM_DATA, 'wrong data value');

        realm.write(function() {
            TestCase.assertThrows(function() {
                obj.boolCol = 'cat';
            });
            TestCase.assertThrows(function() {
                obj.intCol = 'dog';
            });

            TestCase.assertThrows(function() {
                obj.boolCol = null;
            });
            TestCase.assertThrows(function() {
                obj.boolCol = undefined;
            });
            TestCase.assertThrows(function() {
                obj.intCol = null;
            });
            TestCase.assertThrows(function() {
                obj.intCol = undefined;
            });
            TestCase.assertThrows(function() {
                obj.floatCol = null;
            });
            TestCase.assertThrows(function() {
                obj.floatCol = undefined;
            });
            TestCase.assertThrows(function() {
                obj.doubleCol = null;
            });
            TestCase.assertThrows(function() {
                obj.doubleCol = undefined;
            });
            TestCase.assertThrows(function() {
                obj.stringCol = null;
            });
            TestCase.assertThrows(function() {
                obj.stringCol = undefined;
            });
            TestCase.assertThrows(function() {
                obj.dateCol = null;
            });
            TestCase.assertThrows(function() {
                obj.dateCol = undefined;
            });          
            TestCase.assertThrows(function() {
                obj.dataCol = null;
            });
            TestCase.assertThrows(function() {
                obj.dataCol = undefined;
            });
        });

        TestCase.assertThrows(function() {
            obj.boolCol = true;
        }, 'can only set property values in a write transaction');

        TestCase.assertEqual(obj.boolCol, false, 'bool value changed outside transaction');
    },
    testNullableBasicTypesPropertySetters: function() {
        var basicTypesValues = [true, 1, 1.1, 1.11, 'string', new Date(1), RANDOM_DATA];
        var realm = new Realm({schema: [schemas.NullableBasicTypes]});
        var obj, obj1;

        realm.write(function() {
            obj = realm.create('NullableBasicTypesObject', basicTypesValues);
            obj1 = realm.create('NullableBasicTypesObject', basicTypesValues);
            for (var prop of schemas.NullableBasicTypes.properties) {
                obj[prop.name] = null;
                obj1[prop.name] = undefined;
            }
        });

        for (var prop of schemas.NullableBasicTypes.properties) {
            TestCase.assertEqual(obj[prop.name], null);
            TestCase.assertEqual(obj1[prop.name], null);
        }

        realm.write(function() {
            TestCase.assertThrows(function() {
                obj.boolCol = 'cat';
            });
            TestCase.assertThrows(function() {
                obj.intCol = 'dog';
            });
        });

        TestCase.assertThrows(function() {
            obj.boolCol = null;
        }, 'can only set property values in a write transaction');
    },
    testLinkTypesPropertyGetters: function() {
        var realm = new Realm({schema: [schemas.LinkTypes, schemas.TestObject]});
        var obj = null;
        realm.write(function() {
            obj = realm.create('LinkTypesObject', [[1], null, [[3]]]);
        });

        var objVal = obj.objectCol;
        TestCase.assertEqual(typeof objVal, 'object');
        TestCase.assertNotEqual(objVal, null);
        TestCase.assertEqual(objVal.doubleCol, 1);

        TestCase.assertEqual(obj.objectCol1, null);

        var arrayVal = obj.arrayCol;
        TestCase.assertEqual(typeof arrayVal, 'object');
        TestCase.assertNotEqual(arrayVal, null);
        TestCase.assertEqual(arrayVal.length, 1);
        TestCase.assertEqual(arrayVal[0].doubleCol, 3);
    },
    testLinkTypesPropertySetters: function() {
        var realm = new Realm({schema: [schemas.LinkTypes, schemas.TestObject]});
        var objects = realm.objects('TestObject');
        var obj = null;

        realm.write(function() {
            obj = realm.create('LinkTypesObject', [[1], null, [[3]]]);
        });
        TestCase.assertEqual(objects.length, 2);

        TestCase.assertThrows(function() {
            obj.objectCol1 = obj.objectCol;
        }, 'can only set property values in a write transaction');

        // set/reuse object property
        realm.write(function() {
            obj.objectCol1 = obj.objectCol;
        });
        TestCase.assertEqual(obj.objectCol1.doubleCol, 1);
        //TestCase.assertEqual(obj.objectCol, obj.objectCol1);
        TestCase.assertEqual(objects.length, 2);

        realm.write(function() {
            obj.objectCol = null;
            obj.objectCol1 = null;
        });
        TestCase.assertEqual(obj.objectCol, null);
        TestCase.assertEqual(obj.objectCol1, null);

        // set object as JSON
        realm.write(function() {
            obj.objectCol = { doubleCol: 1 };
        });
        TestCase.assertEqual(obj.objectCol.doubleCol, 1);
        TestCase.assertEqual(objects.length, 3);

        // set array property
        realm.write(function() {
            obj.arrayCol = [obj.arrayCol[0], obj.objectCol, realm.create('TestObject', [2])];
        });
        TestCase.assertEqual(objects.length, 4);
        TestCase.assertEqual(obj.arrayCol.length, 3);
        TestCase.assertEqual(obj.arrayCol[0].doubleCol, 3);
        TestCase.assertEqual(obj.arrayCol[1].doubleCol, 1);
        TestCase.assertEqual(obj.arrayCol[2].doubleCol, 2);
    },
    testDataProperties: function() {
        var realm = new Realm({schema: [schemas.DefaultValues, schemas.TestObject]});
        var object;

        // Should be be able to set a data property with a typed array.
        realm.write(function() {
            object = realm.create('DefaultValuesObject', {dataCol: RANDOM_DATA});
        });

        // Data properties should return an instance of an ArrayBuffer.
        TestCase.assertTrue(object.dataCol instanceof ArrayBuffer);
        TestCase.assertArraysEqual(new Uint8Array(object.dataCol), RANDOM_DATA);

        // Should be able to also set a data property to an ArrayBuffer.
        realm.write(function() {
            object.dataCol = RANDOM_DATA.buffer;
        });
        TestCase.assertArraysEqual(new Uint8Array(object.dataCol), RANDOM_DATA);

        realm.write(function() {
            TestCase.assertThrows(function() {
                object.dataCol = true;
            });
            TestCase.assertThrows(function() {
                object.dataCol = 1;
            });
            TestCase.assertThrows(function() {
                object.dataCol = 'data';
            });
            TestCase.assertThrows(function() {
                object.dataCol = [1];
            });
            TestCase.assertThrows(function() {
                object.dataCol = new DataView(RANDOM_DATA.buffer);
            });
        });
    }
});
