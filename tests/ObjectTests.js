'use strict';

var ObjectTests = {
    testBasicTypesPropertyGetters: function() {
    	var basicTypesValues = [true, 1, 1.1, 1.11, 'string', new Date(1), 'DATA'];
    	var realm = new Realm({schema: [BasicTypesObjectSchema]});
    	var object = null;
    	realm.write(function() {
    		object = realm.create('BasicTypesObject', basicTypesValues);
    	});

    	for (var i = 0; i < BasicTypesObjectSchema.properties.length; i++) {
    		var prop = BasicTypesObjectSchema.properties[i];
    		if (prop.type == RealmType.Float) {
    			TestCase.assertEqualWithTolerance(object[prop.name], basicTypesValues[i], 0.000001);
    		}
    		else if (prop.type == RealmType.Date) {
    			TestCase.assertEqual(object[prop.name].getTime(), basicTypesValues[i].getTime());
    		}
    		else {
	    		TestCase.assertEqual(object[prop.name], basicTypesValues[i]);
	    	}
    	}
    },
    testBasicTypesPropertySetters: function() {
    	var basicTypesValues = [true, 1, 1.1, 1.11, 'string', new Date(1), 'DATA'];
    	var realm = new Realm({schema: [BasicTypesObjectSchema]});
    	var obj = null;
    	realm.write(function() {
    		obj = realm.create('BasicTypesObject', basicTypesValues);
    		obj.boolCol = false; 
    		obj.intCol = 2; 
    		obj.floatCol = 2.2;
    		obj.doubleCol = 2.22;
    		obj.stringCol = 'STRING';
    		obj.dateCol = new Date(2); 
    		obj.dataCol = 'b';
   		});
   		TestCase.assertEqual(obj.boolCol, false, 'wrong bool value');
    	TestCase.assertEqual(obj.intCol, 2, 'wrong int value');
    	TestCase.assertEqualWithTolerance(obj.floatCol, 2.2, 0.000001, 'wrong float value');
    	TestCase.assertEqual(obj.doubleCol, 2.22, 'wrong double value');
    	TestCase.assertEqual(obj.stringCol, 'STRING', 'wrong string value');
    	TestCase.assertEqual(obj.dateCol.getTime(), 2, 'wrong date value');
    	TestCase.assertEqual(obj.dataCol, 'b', 'wrong data value');
    },
    testLinkTypesPropertyGetters: function() {
    	var realm = new Realm({schema: [LinkTypesObjectSchema, TestObjectSchema]});
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
        var realm = new Realm({schema: [LinkTypesObjectSchema, TestObjectSchema]});
        var obj = null;
        realm.write(function() {
            obj = realm.create('LinkTypesObject', [[1], undefined, [[3]]]);
        });
        TestCase.assertEqual(realm.objects('TestObject').length, 2);

        // set/reuse object property
        realm.write(function() {
            obj.objectCol1 = obj.objectCol;
        });
        TestCase.assertEqual(obj.objectCol1.doubleCol, 1);
        //TestCase.assertEqual(obj.objectCol, obj.objectCol1);
        TestCase.assertEqual(realm.objects('TestObject').length, 2);

        realm.write(function() {
            obj.objectCol = undefined;
            obj.objectCol1 = null;
        });
        TestCase.assertEqual(obj.objectCol, null);
        TestCase.assertEqual(obj.objectCol1, null);

        // set object as JSON
        realm.write(function() {
            obj.objectCol = { doubleCol: 3 };
        });
        TestCase.assertEqual(obj.objectCol.doubleCol, 3);
        TestCase.assertEqual(realm.objects('TestObject').length, 3);
    },
};
