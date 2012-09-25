function [X,isAdded,nPlane,x,y] = projectOntoGroundPlane(x,y,annotation)

P = getCameraMatrix(annotation);

H = P(:,[1 3 4]);
X = H\[x(:) y(:) ones(length(x),1)]';
X = [X(1,:)./X(3,:); zeros(1,length(x)); X(2,:)./X(3,:)];
isAdded = zeros(1,length(x));
nPlane = cell(1,length(x));
nPlane(:) = {1};