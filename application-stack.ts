import codedeploy = require('@aws-cdk/aws-codedeploy');
import lambda = require('@aws-cdk/aws-lambda');
import apigateway = require('@aws-cdk/aws-apigateway');
import { App, Stack, StackProps } from '@aws-cdk/core';

export interface ApplicationStackProps extends Stack {
    readonly stageName: string;
}

export class ApplicationStack extends Stack {
    public readonly lambdaCode: lambda.CfnParametersCode;

    constructor(app: App, id: string, props: ApplicationStackProps) {
        super(app, id, props);

        this.lambdaCode = lambda.Code.fromCfnParameters();

        const func = new lambda.Function(this, 'lambda', {
            functionName: 'HelloLambda',
            code: this.lambdaCode,
            handler: 'index.handler',
            runtime: lambda.Runtime.NODEJS_12_X,
            environment: {
                STAGE_NAME: props.stageName
            }
        });

        new apigateway.LambdaRestApi(this, 'HelloLambdaRestApi', {
            handler: func,
            endpointExportName: 'HelloLambdaRestApiEndpoint',
            deployOptions: {
                stageName: props.stageName
            }
        });

        const alias = func.currentVersion.addAlias(props.stageName);

        new codedeploy.LambdaDeploymentGroup(this, 'DeploymentGroup', {
            alias,
            deploymentConfig: codedeploy.LambdaDeploymentConfig.ALL_AT_ONCE,
        });
    }
}
