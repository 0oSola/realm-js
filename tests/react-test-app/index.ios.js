////////////////////////////////////////////////////////////////////////////
//
// Copyright 2016 Realm Inc.
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

import {
    AppRegistry,
    StyleSheet,
    Text,
    View,
} from 'react-native';

import React from 'react';
import { runTests } from './tests';

const Realm = require('realm');

Realm.Sync.setLogLevel('error');
var realm;
Realm.Sync.User.login('http://127.0.0.1:9080/', 'ari', 'aaa', function(error, user) {
    console.log(user);

    realm = new Realm({
        sync: {
            user: user, 
            url: 'realm://127.0.0.1:9080/~/demo/realm1'
        }, 
        schema: [{
            name: 'IntObject',
            properties: {
                int: 'int'
            }
        }]
    });

    realm.addListener('change', () => {
        console.log(realm.objects('IntObject'));
    });

    realm.write(() => {
        realm.create('IntObject', {int: realm.objects('IntObject').length});
    });
});


class ReactTests extends React.Component {
    render() {
        return (
            <View style={styles.container}>
                <Text style={styles.button} onPress={runTests}>
                    Tap to Run Tests
                </Text>
                <Text style={styles.instructions}>
                    Press Cmd+R to reload,{'\n'}
                    Cmd+D or shake for dev menu
                </Text>
            </View>
        );
    }
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
        justifyContent: 'center',
        alignItems: 'center',
        backgroundColor: '#F5FCFF',
    },
    button: {
        borderColor: '#cccccc',
        borderRadius: 4,
        borderWidth: 1,
        fontSize: 20,
        textAlign: 'center',
        margin: 20,
        padding: 10,
    },
    instructions: {
        textAlign: 'center',
        color: '#333333',
        marginBottom: 5,
    },
});

AppRegistry.registerComponent('ReactTests', () => ReactTests);
