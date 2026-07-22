![](D:\media/media/image1.png){width="6.3in"
height="0.3229166666666667in"}

**1) Tag the current game server**

![](D:\media/media/image2.png){width="6.3in"
height="3.9381944444444446in"}

**2) Bake AMI from that instance (if AMI not ready)**

![](D:\media/media/image3.png){width="6.3in" height="3.4375in"}

**3) Create launch template (Spot)**

![](D:\media/media/image4.png){width="6.3in"
height="3.426388888888889in"}

**4) Create ASG warm pool**

![](D:\media/media/image5.png){width="6.3in"
height="3.3361111111111112in"}

**5) IAM for MatchMaker**

6)**Create the S3 bucket and
configure**![](D:\media/media/image6.png){width="6.3in"
height="1.5159722222222223in"}

**Static website hosting**

![](D:\media/media/image7.png){width="6.3in"
height="2.220138888888889in"}

**Bucket policy (public read for demo)**

![](D:\media/media/image8.png){width="6.3in"
height="2.111111111111111in"}

**CORS (if login/API calls fail from browser)**

**7)GitHub OIDC → AWS (no long-lived access keys)**

![](D:\media/media/image9.png){width="6.3in"
height="3.015972222222222in"}

**Add GitHub as OIDC provide**

![](D:\media/media/image10.png){width="6.3in"
height="2.9756944444444446in"}

**Attach permissions policy to role**

![](D:\media/media/image11.png){width="6.3in"
height="3.551388888888889in"}

Role Trust policy

![](D:\media/media/image12.png){width="6.3in"
height="4.372222222222222in"}

Repo secret

![](D:\media/media/image13.png){width="6.3in"
height="1.2743055555555556in"}

![](D:\media/media/image14.png){width="6.3in"
height="3.3881944444444443in"}

Roles for **FightingGameServerInstanceRole**

![](D:\media/media/image15.png){width="6.3in"
height="1.0256944444444445in"}

![](D:\media/media/image16.png){width="6.3in"
height="1.3215277777777779in"}

**Modify IAM role**

 

![](D:\media/media/image17.png){width="6.3in"
height="3.354861111111111in"}

Fleet working

![](D:\media/media/image18.png){width="6.3in" height="3.43125in"}

Deploy Success

![](D:\media/media/image19.png){width="6.3in"
height="3.191666666666667in"}

Publishing new version

![](D:\media/media/image20.png){width="6.3in"
height="3.4833333333333334in"}

Redeploy for live versioning

![](D:\media/media/image21.png){width="6.3in"
height="3.5652777777777778in"}

Dormant Prod Stage

![](D:\media/media/image22.png){width="6.3in"
height="1.9131944444444444in"}

![](D:\media/media/image23.png){width="6.3in"
height="3.5770833333333334in"}

Create Role for CodeDeploy

![](D:\media/media/image24.png){width="6.3in"
height="3.6083333333333334in"}

Deployment Group creation

\# 1. Install prerequisites

sudo apt-get update && sudo apt-get install -y ruby-full ruby-webrick
wget gdebi-core

\# 2. Download raw .deb package directly

cd /tmp

wget
https://aws-codedeploy-ap-southeast-1.s3.ap-southeast-1.amazonaws.com/releases/codedeploy-agent_1.8.1-26_all.deb

\# 3. Unpack, fix Ruby dependency declaration, and repack

dpkg-deb -R codedeploy-agent_1.8.1-26_all.deb /tmp/codedeploy-extracted

sed -i \"s/ruby3.2/ruby3.3/g\" /tmp/codedeploy-extracted/DEBIAN/control

dpkg-deb -b /tmp/codedeploy-extracted /tmp/codedeploy-agent_fixed.deb

\# 4. Install patched package and start service

sudo dpkg -i /tmp/codedeploy-agent_fixed.deb

sudo systemctl enable codedeploy-agent

sudo systemctl start codedeploy-agent

sudo systemctl status codedeploy-agent

Update Launch Template, Warm instance và spot instance với code deploy
agent

![](D:\media/media/image25.png){width="6.3in" height="3.31875in"}

![](D:\media/media/image26.png){width="6.3in"
height="2.171527777777778in"}

**Create CodeDeploy EC2 application**

![](D:\media/media/image27.png){width="6.3in"
height="3.704861111111111in"}

**EC2 Deployment group config**

![](D:\media/media/image28.png){width="6.3in"
height="3.4659722222222222in"}

**Successful CodeDeploy Job**

![](D:\media/media/image29.png){width="6.3in" height="3.075in"}

**Deployment history**

**8)Async Processing**

![](D:\media/media/image30.png){width="6.3in"
height="3.386111111111111in"}

**DynamoDB setup**

![](D:\media/media/image31.png){width="6.3in"
height="3.497916666666667in"}

**Finished State application to DynamoDB**

![](D:\media/media/image32.png){width="6.3in"
height="1.0486111111111112in"}

![](D:\media/media/image33.png){width="6.3in"
height="3.6381944444444443in"}

**Created new Match analytic role**

![](D:\media/media/image34.png){width="6.3in"
height="3.127083333333333in"}

**Created Active stream reading Policy**

![](D:\media/media/image35.png){width="6.3in"
height="3.6597222222222223in"}

**Created Role for MatchAnalytic Lambda**

![](D:\media/media/image36.png){width="6.3in"
height="3.4631944444444445in"}

**Created Match Analytic Lambda**

![](D:\media/media/image37.png){width="6.3in"
height="3.6013888888888888in"}

**DynamoDB Data**

![](D:\media/media/image38.png){width="6.3in"
height="0.9354166666666667in"}

**Subnet Table**

**Cleaning up resources**

![](D:\media/media/image39.png){width="6.3in" height="3.4in"}

**Delete CodeDeploy Application**

![](D:\media/media/image40.png){width="6.3in"
height="3.4631944444444445in"}

**Delete ASG**

![](D:\media/media/image41.png){width="6.3in" height="3.4125in"}

**Delete EC2 Instances**

![](D:\media/media/image42.png){width="6.3in"
height="3.379166666666667in"}

**Delete Launch Template**

![](D:\media/media/image43.png){width="6.3in"
height="3.3534722222222224in"}

**Delete Api from API Gateway**

![](D:\media/media/image44.png){width="6.3in"
height="3.3430555555555554in"}

**Delete Lambda functions**

![](D:\media/media/image45.png){width="6.3in" height="3.375in"}

**Delete DynamoDB Tables**

![](D:\media/media/image46.png){width="6.3in"
height="3.4722222222222223in"}

**Emptying S3 Bucket**

![](D:\media/media/image47.png){width="6.3in"
height="3.3381944444444445in"}

**Delete S3 Bucket**

![](D:\media/media/image48.png){width="6.3in"
height="3.4479166666666665in"}

**Delete VPC**

![](D:\media/media/image49.png){width="6.3in"
height="3.473611111111111in"}

**Delete IAM Roles**
